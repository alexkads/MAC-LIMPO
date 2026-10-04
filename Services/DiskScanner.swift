// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import Foundation

/// Varre uma árvore e devolve um `DiskScanIndex` com cada pasta e arquivo.
///
/// Segue o motor básico do WinDirStat (FinderBasic.cpp + CItem::ScanItems):
///
/// - **Leitura em lote por pasta.** O WinDirStat usa `NtQueryDirectoryFile` com
///   buffer de 4 MiB: uma chamada traz centenas de entradas já com tamanho,
///   atributos e datas. O equivalente no macOS é `getattrlistbulk(2)` — nome,
///   tipo, tamanho alocado, tamanho lógico, data e inode de muitas entradas por
///   chamada, sem um `lstat` por arquivo.
/// - **Workers paralelos.** Como o `ScanningThreads` do WinDirStat, threads
///   tiram pastas de uma fila e enfileiram as subpastas (BlockingQueue.h); a
///   quantidade e o buffer vêm do `ScanTuning` (hardware e tipo de volume).
///
/// O motor rápido do WinDirStat lê a MFT do NTFS direto do volume; o APFS não
/// tem equivalente acessível sem root, então este é o caminho de lá também
/// quando a MFT não está disponível.
///
/// Depois da leitura, uma passada monta o índice em pré-ordem (a subárvore de
/// `i` é `i+1...subtreeEnd[i]`) e soma os tamanhos de baixo para cima. Espaço
/// físico pelo tamanho alocado (um `Docker.raw` esparso conta o que ocupa);
/// hardlinks contam uma vez; montagens (DeviceFS, runtimes de simulador) não
/// são atravessadas.
enum DiskScanner {
    struct Progress: Sendable {
        let items: Int
        /// Inodes em uso no volume — estimativa do total, para a barra de progresso.
        let estimatedItems: Int
        let physicalBytes: Int64
        let currentPath: String
    }

    /// `tuning` padrão: threads e buffer escolhidos para o volume de `root`
    /// nesta máquina (ScanTuning) — o equivalente ao ScanningThreads do
    /// WinDirStat, só que ajustado ao hardware em vez de fixo.
    static func scan(
        root: String,
        tuning: ScanTuning? = nil,
        isCancelled: @escaping @Sendable () -> Bool,
        progress: @escaping @Sendable (Progress) -> Void
    ) -> DiskScanIndex? {
        var rootStat = stat()
        guard lstat(root, &rootStat) == 0, (rootStat.st_mode & S_IFMT) == S_IFDIR else { return nil }

        let estimated = estimatedItemCount(at: root)
        let queue = WorkQueue(rootDevice: Int32(rootStat.st_dev), estimated: estimated, progress: progress)
        queue.push([(job: 0, path: root)], newJobs: 1)

        let tuning = tuning ?? ScanTuning.recommended(for: root)
        let workerCount = max(1, min(16, tuning.threads))
        let bufferSize = tuning.bufferSize
        let stores = (0 ..< workerCount).map { _ in WorkerStore() }
        let group = DispatchGroup()
        for (worker, store) in stores.enumerated() {
            group.enter()
            let thread = Thread {
                runWorker(UInt8(worker), store: store, queue: queue, bufferSize: bufferSize, isCancelled: isCancelled)
                group.leave()
            }
            thread.stackSize = 1 << 20
            thread.qualityOfService = .userInitiated
            thread.start()
        }
        group.wait()
        guard !isCancelled() else { return nil }

        return buildIndex(
            root: root, rootModified: UInt32(clamping: rootStat.st_mtimespec.tv_sec), queue: queue, stores: stores
        )
    }

    // MARK: - Leitura (workers)

    /// Entradas lidas por um worker. Uma pasta inteira é lida pelo mesmo worker,
    /// então as entradas de cada pasta ficam contíguas aqui.
    final class WorkerStore: @unchecked Sendable {
        var nameBytes = ContiguousArray<UInt8>()
        var nameOffset = ContiguousArray<UInt32>()
        var nameLength = ContiguousArray<UInt16>()
        var isDirectory = ContiguousArray<Bool>()
        var physical = ContiguousArray<Int64>()
        var logical = ContiguousArray<Int64>()
        var modified = ContiguousArray<UInt32>()
        /// Inode, só para arquivos com mais de um link (hardlinks); 0 nos demais.
        var hardLinkID = ContiguousArray<UInt64>()
        /// Job da subpasta (-1 para arquivos e para pastas não percorridas).
        var childJob = ContiguousArray<Int32>()

        init() {
            let capacity = 1 << 18
            nameBytes.reserveCapacity(capacity * 20)
            nameOffset.reserveCapacity(capacity)
            nameLength.reserveCapacity(capacity)
            isDirectory.reserveCapacity(capacity)
            physical.reserveCapacity(capacity)
            logical.reserveCapacity(capacity)
            modified.reserveCapacity(capacity)
            hardLinkID.reserveCapacity(capacity)
            childJob.reserveCapacity(capacity)
        }

        var count: Int { isDirectory.count }
    }

    /// Onde estão as entradas de uma pasta lida.
    struct JobRange {
        var worker: UInt8 = 0
        var start: Int32 = 0
        var count: Int32 = 0
        var unreadable = false
    }

    /// Fila de pastas pendentes compartilhada pelos workers (BlockingQueue).
    final class WorkQueue: @unchecked Sendable {
        private let condition = NSCondition()
        private var pending: [(job: Int32, path: String)] = []
        private var inFlight = 0
        private var jobCount: Int32 = 0
        private var ranges: [JobRange] = []
        let rootDevice: Int32

        private let estimated: Int
        private let progress: @Sendable (Progress) -> Void
        private var items = 0
        private var bytes: Int64 = 0
        private var lastReport = Date.distantPast

        init(rootDevice: Int32, estimated: Int, progress: @escaping @Sendable (Progress) -> Void) {
            self.rootDevice = rootDevice
            self.estimated = estimated
            self.progress = progress
            ranges.reserveCapacity(1 << 16)
        }

        /// Reserva ids consecutivos para novas pastas.
        func reserveJobs(_ count: Int) -> Int32 {
            condition.lock()
            defer { condition.unlock() }
            let first = jobCount
            jobCount += Int32(count)
            return first
        }

        func push(_ jobs: [(job: Int32, path: String)], newJobs: Int32 = 0) {
            condition.lock()
            jobCount += newJobs
            pending.append(contentsOf: jobs)
            condition.unlock()
            condition.broadcast()
        }

        /// Próxima pasta, ou nil quando não há mais trabalho (fila vazia e
        /// ninguém lendo uma pasta que ainda pode enfileirar outras).
        func pop(isCancelled: () -> Bool) -> (job: Int32, path: String)? {
            condition.lock()
            defer { condition.unlock() }
            while true {
                if isCancelled() {
                    condition.broadcast()
                    return nil
                }
                if let next = pending.popLast() {
                    inFlight += 1
                    return next
                }
                if inFlight == 0 {
                    condition.broadcast()
                    return nil
                }
                condition.wait(until: Date().addingTimeInterval(0.25))
            }
        }

        func complete(_ job: Int32, range: JobRange, children: [(job: Int32, path: String)], physical: Int64, path: String) {
            condition.lock()
            let index = Int(job)
            if ranges.count <= index {
                ranges.append(contentsOf: repeatElement(JobRange(), count: index - ranges.count + 1))
            }
            ranges[index] = range
            pending.append(contentsOf: children)
            inFlight -= 1
            items += Int(range.count)
            bytes += physical
            let now = Date()
            let report = now.timeIntervalSince(lastReport) > 0.2
            if report { lastReport = now }
            let snapshot = Progress(items: items, estimatedItems: estimated, physicalBytes: bytes, currentPath: path)
            let wake = !children.isEmpty || inFlight == 0
            condition.unlock()
            if wake { condition.broadcast() }
            if report { progress(snapshot) }
        }

        func finalRanges() -> [JobRange] {
            condition.lock()
            defer { condition.unlock() }
            if ranges.count < Int(jobCount) {
                ranges.append(contentsOf: repeatElement(JobRange(), count: Int(jobCount) - ranges.count))
            }
            return ranges
        }
    }

    // Constantes de <sys/attr.h>.
    private static let attrCmnName: UInt32 = 0x0000_0001
    private static let attrCmnDevID: UInt32 = 0x0000_0002
    private static let attrCmnObjType: UInt32 = 0x0000_0008
    private static let attrCmnModTime: UInt32 = 0x0000_0400
    private static let attrCmnFileID: UInt32 = 0x0200_0000
    private static let attrCmnError: UInt32 = 0x2000_0000
    private static let attrCmnReturnedAttrs: UInt32 = 0x8000_0000
    private static let attrDirMountStatus: UInt32 = 0x0000_0004
    private static let dirMountStatusMountPoint: UInt32 = 0x0000_0001
    private static let attrFileLinkCount: UInt32 = 0x0000_0001
    private static let attrFileTotalSize: UInt32 = 0x0000_0002
    private static let attrFileAllocSize: UInt32 = 0x0000_0004
    private static let fsoptPackInvalAttrs: UInt64 = 0x0000_0008
    private static let vdir: UInt32 = 2

    private static func runWorker(
        _ worker: UInt8,
        store: WorkerStore,
        queue: WorkQueue,
        bufferSize: Int,
        isCancelled: () -> Bool
    ) {
        var attributes = attrlist()
        attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = attrCmnReturnedAttrs | attrCmnError | attrCmnName | attrCmnDevID
            | attrCmnObjType | attrCmnModTime | attrCmnFileID
        attributes.dirattr = attrDirMountStatus
        attributes.fileattr = attrFileLinkCount | attrFileTotalSize | attrFileAllocSize

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        while let (job, path) = queue.pop(isCancelled: isCancelled) {
            var range = JobRange(worker: worker, start: Int32(store.count))
            var physicalSum: Int64 = 0
            var childDirs: [(entry: Int, name: String)] = []

            let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if fd < 0 {
                range.unreadable = true
                queue.complete(job, range: range, children: [], physical: 0, path: path)
                continue
            }

            while true {
                let count = getattrlistbulk(fd, &attributes, buffer, bufferSize, fsoptPackInvalAttrs)
                if count < 0 {
                    if store.count == Int(range.start) { range.unreadable = true }
                    break
                }
                if count == 0 { break }

                var entry = UnsafeRawPointer(buffer)
                for _ in 0 ..< Int(count) {
                    let length = Int(entry.loadUnaligned(as: UInt32.self))
                    defer { entry += length }
                    // Layout: length(4) + attribute_set_t(20), ATTR_CMN_ERROR, os
                    // comuns na ordem dos bits e então os de pasta OU os de
                    // arquivo — FSOPT_PACK_INVAL_ATTRS não empacota os atributos
                    // de pasta numa entrada de arquivo nem vice-versa.
                    var field = entry + 24
                    let error = field.loadUnaligned(as: UInt32.self); field += 4
                    let nameReference = field
                    let nameOffset = Int(field.loadUnaligned(as: Int32.self))
                    let nameLength = Int(field.loadUnaligned(fromByteOffset: 4, as: UInt32.self)); field += 8
                    let device = field.loadUnaligned(as: Int32.self); field += 4
                    let type = field.loadUnaligned(as: UInt32.self); field += 4
                    let seconds = field.loadUnaligned(as: Int.self); field += 16 // timespec
                    let fileID = field.loadUnaligned(as: UInt64.self); field += 8
                    let returnedDirectoryAttributes = entry.loadUnaligned(fromByteOffset: 12, as: UInt32.self)
                    var mountStatus: UInt32 = 0
                    var linkCount: UInt32 = 0, totalSize: Int64 = 0, allocSize: Int64 = 0
                    if returnedDirectoryAttributes != 0 {
                        mountStatus = field.loadUnaligned(as: UInt32.self)
                    } else {
                        linkCount = field.loadUnaligned(as: UInt32.self); field += 4
                        totalSize = field.loadUnaligned(as: Int64.self); field += 8
                        allocSize = field.loadUnaligned(as: Int64.self)
                    }
                    guard error == 0 else { continue }

                    // O comprimento do nome inclui o NUL final.
                    let name = UnsafeRawBufferPointer(start: nameReference + nameOffset, count: max(0, nameLength - 1))
                    let directory = type == vdir

                    store.nameOffset.append(UInt32(store.nameBytes.count))
                    store.nameLength.append(UInt16(min(name.count, Int(UInt16.max))))
                    store.nameBytes.append(contentsOf: name)
                    store.isDirectory.append(directory)
                    store.modified.append(UInt32(clamping: seconds))
                    store.childJob.append(-1)
                    if directory {
                        store.physical.append(0)
                        store.logical.append(0)
                        store.hardLinkID.append(0)
                        let crossesMount = device != queue.rootDevice || mountStatus & dirMountStatusMountPoint != 0
                        if !crossesMount {
                            childDirs.append((store.count - 1, String(decoding: name, as: UTF8.self)))
                        }
                    } else {
                        // Symlinks e outros tipos contam o que ocupam, como o lstat.
                        store.physical.append(allocSize)
                        store.logical.append(totalSize)
                        store.hardLinkID.append(linkCount > 1 ? fileID : 0)
                        physicalSum += allocSize
                    }
                }
            }
            close(fd)

            var children: [(job: Int32, path: String)] = []
            if !childDirs.isEmpty {
                let first = queue.reserveJobs(childDirs.count)
                children.reserveCapacity(childDirs.count)
                for (offset, child) in childDirs.enumerated() {
                    let childJob = first + Int32(offset)
                    store.childJob[child.entry] = childJob
                    children.append((childJob, path.hasSuffix("/") ? path + child.name : path + "/" + child.name))
                }
            }
            range.count = Int32(store.count) - range.start
            queue.complete(job, range: range, children: children, physical: physicalSum, path: path)
        }
    }

    // MARK: - Montagem do índice

    private static func buildIndex(
        root: String,
        rootModified: UInt32,
        queue: WorkQueue,
        stores: [WorkerStore]
    ) -> DiskScanIndex? {
        let ranges = queue.finalRanges()
        let total = stores.reduce(0) { $0 + $1.count } + 1
        let index = DiskScanIndex(rootPath: root)
        reserve(index, capacity: total, nameBytes: stores.reduce(0) { $0 + $1.nameBytes.count })

        var extensionLookup: [String: Int32] = [:]
        var seenHardLinks = Set<UInt64>()

        func append(
            parent: Int32, name: UnsafeBufferPointer<UInt8>?, isDirectory: Bool,
            physical: Int64, logical: Int64, modified: UInt32, unreadable: Bool
        ) -> Int32 {
            let i = Int32(index.count)
            var flags: UInt8 = isDirectory ? DiskScanIndex.isDirectory : 0
            if unreadable {
                flags |= DiskScanIndex.isUnreadable
                index.unreadableCount += 1
            }
            var extensionIndex: Int32 = -1
            index.nameOffset.append(UInt32(index.nameBytes.count))
            index.nameLength.append(UInt16(name?.count ?? 0))
            if let name {
                index.nameBytes.append(contentsOf: name)
                if !isDirectory {
                    let ext = fileExtension(name)
                    if let known = extensionLookup[ext] {
                        extensionIndex = known
                    } else {
                        extensionIndex = Int32(index.extensions.count)
                        extensionLookup[ext] = extensionIndex
                        index.extensions.append(ext)
                        index.extensionPhysical.append(0)
                        index.extensionLogical.append(0)
                        index.extensionFiles.append(0)
                    }
                    index.extensionPhysical[Int(extensionIndex)] += physical
                    index.extensionLogical[Int(extensionIndex)] += logical
                    index.extensionFiles[Int(extensionIndex)] += 1
                }
            }
            index.parent.append(parent)
            index.firstChild.append(-1)
            index.nextSibling.append(-1)
            index.subtreeEnd.append(i)
            index.physical.append(physical)
            index.logical.append(isDirectory ? 0 : logical)
            index.fileCount.append(isDirectory ? 0 : 1)
            index.folderCount.append(0)
            index.modified.append(modified)
            index.flags.append(flags)
            index.extensionIndex.append(extensionIndex)
            if parent >= 0 {
                index.nextSibling[Int(i)] = index.firstChild[Int(parent)]
                index.firstChild[Int(parent)] = i
            }
            return i
        }

        /// Fecha uma pasta: totais sobem para o pai (pós-ordem).
        func finish(_ i: Int32) {
            index.subtreeEnd[Int(i)] = Int32(index.count - 1)
            let parent = index.parent[Int(i)]
            guard parent >= 0 else { return }
            let p = Int(parent), c = Int(i)
            index.physical[p] += index.physical[c]
            index.logical[p] += index.logical[c]
            index.fileCount[p] += index.fileCount[c]
            index.folderCount[p] += index.folderCount[c] + 1
            index.modified[p] = max(index.modified[p], index.modified[c])
        }

        // Pré-ordem com pilha explícita: (item da pasta, entradas dela, próxima).
        let rootRange = ranges.first ?? JobRange()
        let rootItem = append(parent: -1, name: nil, isDirectory: true, physical: 0, logical: 0,
                              modified: rootModified, unreadable: rootRange.unreadable)
        var stack: [(item: Int32, range: JobRange, next: Int32)] = [(rootItem, rootRange, 0)]

        while let frame = stack.last {
            guard frame.next < frame.range.count else {
                finish(frame.item)
                stack.removeLast()
                continue
            }
            stack[stack.count - 1].next += 1

            let store = stores[Int(frame.range.worker)]
            let k = Int(frame.range.start + frame.next)
            let isDirectory = store.isDirectory[k]
            var physical = store.physical[k]
            var logical = store.logical[k]
            if !isDirectory, store.hardLinkID[k] != 0, !seenHardLinks.insert(store.hardLinkID[k]).inserted {
                physical = 0 // mesmo arquivo, outro nome: já contado
                logical = 0
            }
            let childJob = store.childJob[k]
            let childRange = childJob >= 0 && Int(childJob) < ranges.count ? ranges[Int(childJob)] : JobRange()
            let start = Int(store.nameOffset[k])
            let item = store.nameBytes.withUnsafeBufferPointer { bytes in
                append(
                    parent: frame.item,
                    name: UnsafeBufferPointer(rebasing: bytes[start ..< start + Int(store.nameLength[k])]),
                    isDirectory: isDirectory, physical: physical, logical: logical,
                    modified: store.modified[k], unreadable: isDirectory && childRange.unreadable
                )
            }
            if !isDirectory {
                let parent = Int(frame.item)
                index.physical[parent] += physical
                index.logical[parent] += logical
                index.fileCount[parent] += 1
                index.modified[parent] = max(index.modified[parent], store.modified[k])
            } else if childJob >= 0 {
                stack.append((item, childRange, 0))
            } else {
                finish(item) // montagem não atravessada: pasta vazia
            }
        }

        return index.count > 0 ? index : nil
    }

    /// CItem::GetExtension: do último "." até o fim, em minúsculas, com o ponto
    /// (".zshrc" → ".zshrc"); "" se o nome não tiver ponto.
    static func fileExtension(_ name: UnsafeBufferPointer<UInt8>) -> String {
        guard let dot = name.lastIndex(of: 0x2E) else { return "" }
        return String(decoding: UnsafeBufferPointer(rebasing: name[dot...]), as: UTF8.self).lowercased()
    }

    /// Inodes em uso no volume de `path` (≈ quantidade de itens).
    private static func estimatedItemCount(at path: String) -> Int {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return 0 }
        return Int(stats.f_files) - Int(stats.f_ffree)
    }

    private static func reserve(_ index: DiskScanIndex, capacity: Int, nameBytes: Int) {
        index.parent.reserveCapacity(capacity)
        index.firstChild.reserveCapacity(capacity)
        index.nextSibling.reserveCapacity(capacity)
        index.subtreeEnd.reserveCapacity(capacity)
        index.physical.reserveCapacity(capacity)
        index.logical.reserveCapacity(capacity)
        index.fileCount.reserveCapacity(capacity)
        index.folderCount.reserveCapacity(capacity)
        index.modified.reserveCapacity(capacity)
        index.flags.reserveCapacity(capacity)
        index.extensionIndex.reserveCapacity(capacity)
        index.nameOffset.reserveCapacity(capacity)
        index.nameLength.reserveCapacity(capacity)
        index.nameBytes.reserveCapacity(nameBytes)
    }
}
