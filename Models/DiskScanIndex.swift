import Foundation

/// Todos os itens de uma varredura (pastas e arquivos), em arrays paralelos.
///
/// Um disco de desenvolvedor tem milhões de arquivos; um objeto por item custaria
/// gigabytes. Aqui cada item é um índice, e os campos vivem em arrays contíguos
/// (~50 bytes por item, nomes inclusos). Os índices seguem a pré-ordem da
/// varredura, então a subárvore de `i` é exatamente `i+1 ... subtreeEnd[i]`.
///
/// Imutável depois de pronto, exceto `remove`, que só o view model chama no
/// MainActor, sem render em andamento.
final class DiskScanIndex: @unchecked Sendable {
    // MARK: Campos por item

    var parent = ContiguousArray<Int32>()
    var firstChild = ContiguousArray<Int32>()
    var nextSibling = ContiguousArray<Int32>()
    var subtreeEnd = ContiguousArray<Int32>()
    /// Espaço alocado em disco (o que de fato ocupa; `st_blocks * 512`).
    var physical = ContiguousArray<Int64>()
    /// Tamanho lógico (`st_size`). Difere em arquivos esparsos e comprimidos.
    var logical = ContiguousArray<Int64>()
    /// Arquivos na subárvore (1 para arquivo).
    var fileCount = ContiguousArray<Int32>()
    /// Pastas na subárvore, sem contar a própria (coluna "Folders").
    var folderCount = ContiguousArray<Int32>()
    /// Última modificação (segundos desde 1970). Pastas: o máximo da subárvore,
    /// como o "Last Change" do WinDirStat (Item.cpp:612-621).
    var modified = ContiguousArray<UInt32>()
    var flags = ContiguousArray<UInt8>()
    /// Índice em `extensions` (arquivos), ou -1 (pastas).
    var extensionIndex = ContiguousArray<Int32>()

    var nameBytes = ContiguousArray<UInt8>()
    var nameOffset = ContiguousArray<UInt32>()
    var nameLength = ContiguousArray<UInt16>()

    // MARK: Por extensão

    /// Chave da extensão como no WinDirStat (Item.cpp, GetExtension): o texto a
    /// partir do último ".", em minúsculas, com o ponto; "" se não houver ponto.
    var extensions: [String] = []
    var extensionPhysical: [Int64] = []
    /// A coluna "Bytes" da lista de extensões usa o tamanho lógico.
    var extensionLogical: [Int64] = []
    var extensionFiles: [Int32] = []

    /// Caminho real da raiz varrida.
    let rootPath: String
    /// Pastas que não puderam ser lidas.
    var unreadableCount = 0

    static let isDirectory: UInt8 = 1
    static let isUnreadable: UInt8 = 2
    static let isRemoved: UInt8 = 4

    init(rootPath: String) {
        self.rootPath = rootPath
    }

    var count: Int { parent.count }
    var root: Int32 { 0 }

    func isDirectory(_ i: Int32) -> Bool { flags[Int(i)] & Self.isDirectory != 0 }
    func isUnreadable(_ i: Int32) -> Bool { flags[Int(i)] & Self.isUnreadable != 0 }
    func isRemoved(_ i: Int32) -> Bool { flags[Int(i)] & Self.isRemoved != 0 }

    func name(_ i: Int32) -> String {
        if i == root { return rootPath }
        let start = Int(nameOffset[Int(i)])
        let length = Int(nameLength[Int(i)])
        return nameBytes.withUnsafeBufferPointer { buffer in
            String(decoding: UnsafeBufferPointer(rebasing: buffer[start ..< start + length]), as: UTF8.self)
        }
    }

    func path(_ i: Int32) -> String {
        var components: [String] = []
        var cursor = i
        while cursor != root {
            components.append(name(cursor))
            cursor = parent[Int(cursor)]
        }
        return components.reversed().reduce(rootPath) { ($0 as NSString).appendingPathComponent($1) }
    }

    func extensionName(_ i: Int32) -> String? {
        let index = extensionIndex[Int(i)]
        return index >= 0 ? extensions[Int(index)] : nil
    }

    /// Ancestrais do item, da raiz até ele (inclusive).
    func lineage(_ i: Int32) -> [Int32] {
        var chain: [Int32] = [i]
        var cursor = i
        while cursor != root {
            cursor = parent[Int(cursor)]
            chain.append(cursor)
        }
        return chain.reversed()
    }

    func isAncestor(_ a: Int32, of b: Int32) -> Bool {
        b > a && b <= subtreeEnd[Int(a)]
    }

    // MARK: Filhos

    private var sortedChildrenCache: [Int32: [Int32]] = [:]
    private let cacheLock = NSLock()

    /// Filhos do item, maiores primeiro, sem os removidos.
    func children(_ i: Int32) -> [Int32] {
        cacheLock.lock()
        if let cached = sortedChildrenCache[i] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var result: [Int32] = []
        var child = firstChild[Int(i)]
        while child >= 0 {
            if flags[Int(child)] & Self.isRemoved == 0 { result.append(child) }
            child = nextSibling[Int(child)]
        }
        result.sort { physical[Int($0)] > physical[Int($1)] }

        cacheLock.lock()
        sortedChildrenCache[i] = result
        cacheLock.unlock()
        return result
    }

    func hasChildren(_ i: Int32) -> Bool { firstChild[Int(i)] >= 0 }

    // MARK: Consultas

    /// Os `limit` maiores arquivos dentro de `i`. A subárvore é um intervalo
    /// contíguo de índices, então isto é uma varredura linear sem recursão.
    func largestFiles(in i: Int32, limit: Int, logicalSize: Bool = false) -> [Int32] {
        let sizes = logicalSize ? logical : physical
        let start = Int(i), end = Int(subtreeEnd[Int(i)])
        var top: [Int32] = []
        var threshold: Int64 = -1
        for index in start ... end where flags[index] & (Self.isDirectory | Self.isRemoved) == 0 {
            let size = sizes[index]
            guard top.count < limit || size > threshold else { continue }
            top.append(Int32(index))
            if top.count >= limit * 2 {
                top.sort { sizes[Int($0)] > sizes[Int($1)] }
                top.removeLast(top.count - limit)
                threshold = sizes[Int(top.last!)]
            }
        }
        top.sort { sizes[Int($0)] > sizes[Int($1)] }
        return Array(top.prefix(limit))
    }

    // MARK: Remoção (Lixeira)

    /// Marca o item como removido e desconta tamanhos dos ancestrais e das
    /// estatísticas de extensão.
    func remove(_ i: Int32) {
        guard i != root, !isRemoved(i) else { return }
        let removedPhysical = physical[Int(i)]
        let removedLogical = logical[Int(i)]
        let removedFiles = fileCount[Int(i)]
        let removedFolders = folderCount[Int(i)] + (isDirectory(i) ? 1 : 0)

        // Extensões: desconta cada arquivo da subárvore.
        for index in Int(i) ... Int(subtreeEnd[Int(i)]) where flags[index] & Self.isDirectory == 0 {
            let ext = extensionIndex[index]
            if ext >= 0 {
                extensionPhysical[Int(ext)] -= physical[index]
                extensionLogical[Int(ext)] -= logical[index]
                extensionFiles[Int(ext)] -= 1
            }
        }

        flags[Int(i)] |= Self.isRemoved
        var cursor = parent[Int(i)]
        while cursor >= 0 {
            physical[Int(cursor)] -= removedPhysical
            logical[Int(cursor)] -= removedLogical
            fileCount[Int(cursor)] -= removedFiles
            folderCount[Int(cursor)] -= removedFolders
            if cursor == root { break }
            cursor = parent[Int(cursor)]
        }
        cacheLock.lock()
        sortedChildrenCache[parent[Int(i)]] = nil
        cacheLock.unlock()
    }
}
