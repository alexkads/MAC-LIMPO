import Foundation

/// Coleta os dados do Raio-X: a conta do container APFS e os tamanhos do
/// volume Data. Nada aqui apaga coisa alguma, exceto `trash`, que só roda por
/// ação explícita do usuário.
final class DiskXRayService: @unchecked Sendable {
    static let shared = DiskXRayService()

    /// Raiz real do volume de dados. Medir aqui com `du -x` cobre tudo que é
    /// do usuário e dos apps, sem entrar no volume do sistema nem em montagens
    /// (DeviceFS do iPhone, runtimes de simulador, discos externos).
    static let dataRoot = "/System/Volumes/Data"

    /// Resultado de uma passada do `du`.
    struct Measurement: Sendable {
        let sizes: [String: Int64]
        let unreadable: Set<String>
        let cancelled: Bool
    }

    // MARK: - APFS

    func overview() -> DiskOverview? {
        guard let device = Self.device(of: Self.dataRoot) else { return nil }
        let result = ShellExecutor.shared.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"], timeout: 30)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else { return nil }
        return DiskOverview.parse(plist: data, dataDevice: device)
    }

    /// "disk3s5" para o volume montado em `path`.
    private static func device(of path: String) -> String? {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return nil }
        let from = withUnsafeBytes(of: stats.f_mntfromname) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return from.hasPrefix("/dev/") ? String(from.dropFirst(5)) : from
    }

    // MARK: - du

    /// Mede `root` com `du -x -k -d depth`, reportando o progresso pela soma dos
    /// filhos diretos já concluídos (o `du` imprime cada pasta ao terminá-la).
    /// Cancelar a Task encerra o processo.
    func measure(
        root: String,
        depth: Int,
        progress: @escaping @Sendable (_ measuredBytes: Int64, _ currentPath: String) -> Void
    ) async -> Measurement {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-x", "-k", "-d", String(depth), root]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = nil

        let collector = OutputCollector(root: root, progress: progress)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { collector.appendOut(chunk) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { collector.appendErr(chunk) }
        }

        let exited: Void? = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void?, Never>) in
                process.terminationHandler = { _ in continuation.resume(returning: ()) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(returning: nil)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        // Drena o que ficou nos pipes depois do término.
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        collector.appendOut(stdout.fileHandleForReading.readDataToEndOfFile())
        collector.appendErr(stderr.fileHandleForReading.readDataToEndOfFile())

        let (out, err) = collector.finish()
        return Measurement(
            sizes: DuOutput.parseSizes(out),
            unreadable: DuOutput.parseUnreadable(err),
            cancelled: exited == nil || Task.isCancelled
        )
    }

    // MARK: - Arquivos de uma pasta

    /// Arquivos diretos de `path` (não recursivo), com o espaço alocado.
    func files(in path: String) -> [(name: String, path: String, size: Int64)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys, options: []
        )) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                return nil
            }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            return (url.lastPathComponent, url.path, size)
        }
    }

    /// Os `limit` maiores arquivos em qualquer nível abaixo de `path`, pelo
    /// espaço alocado. Fica no mesmo volume (não entra em montagens) e inclui
    /// ocultos e o conteúdo de pacotes (.app, .photoslibrary…).
    func largestFiles(
        under path: String,
        limit: Int,
        isCancelled: @escaping @Sendable () -> Bool
    ) -> [(name: String, path: String, size: Int64)] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .volumeIdentifierKey
        ]
        let rootURL = URL(fileURLWithPath: path)
        let rootVolume = try? rootURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return [] }

        var top: [(name: String, path: String, size: Int64)] = []
        var smallestKept: Int64 = 0
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited % 2000 == 0, isCancelled() { return [] }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if let volume = values.volumeIdentifier as? NSObject, let rootVolume, !volume.isEqual(rootVolume) {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard top.count < limit || size > smallestKept else { continue }
            top.append((url.lastPathComponent, url.path, size))
            if top.count > limit * 2 {
                top.sort { $0.size > $1.size }
                top.removeLast(top.count - limit)
                smallestKept = top.last?.size ?? 0
            }
        }
        top.sort { $0.size > $1.size }
        return Array(top.prefix(limit))
    }

    // MARK: - Ações

    func trash(path: String) -> Bool {
        FileSystemHelper.shared.trashItem(atPath: path)
    }
}

/// Junta a saída do `du` enquanto ela chega, e calcula o progresso pelas linhas
/// dos filhos diretos da raiz (cada uma é uma pasta de primeiro nível concluída).
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let root: String
    private let progress: @Sendable (Int64, String) -> Void
    private var out = Data()
    private var err = Data()
    private var pendingLine = Data()
    private var topLevelBytes: Int64 = 0
    private var lastReport = Date.distantPast

    init(root: String, progress: @escaping @Sendable (Int64, String) -> Void) {
        self.root = root
        self.progress = progress
    }

    func appendOut(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        out.append(chunk)
        pendingLine.append(chunk)
        var lastPath = ""
        while let newline = pendingLine.firstIndex(of: 0x0A) {
            let line = String(decoding: pendingLine[pendingLine.startIndex ..< newline], as: UTF8.self)
            pendingLine.removeSubrange(pendingLine.startIndex ... newline)
            guard let tab = line.firstIndex(of: "\t"), let kb = Int64(line[..<tab]) else { continue }
            let path = String(line[line.index(after: tab)...])
            lastPath = path
            if (path as NSString).deletingLastPathComponent == root { topLevelBytes += kb * 1024 }
        }
        let now = Date()
        let shouldReport = !lastPath.isEmpty && now.timeIntervalSince(lastReport) > 0.15
        if shouldReport { lastReport = now }
        let bytes = topLevelBytes
        lock.unlock()
        if shouldReport { progress(bytes, lastPath) }
    }

    func appendErr(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        err.append(chunk)
        lock.unlock()
    }

    func finish() -> (String, String) {
        lock.lock()
        defer { lock.unlock() }
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}
