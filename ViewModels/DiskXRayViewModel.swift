import AppKit
import Foundation

@MainActor
final class DiskXRayViewModel: ObservableObject {
    @Published private(set) var overview: DiskOverview?
    @Published private(set) var root: XRayNode?
    @Published private(set) var current: XRayNode?
    @Published private(set) var breadcrumbs: [XRayNode] = []
    @Published var selected: XRayNode?

    @Published private(set) var isScanning = false
    @Published private(set) var measuredBytes: Int64 = 0
    @Published private(set) var currentPath = ""
    @Published private(set) var scanStarted: Date?
    @Published private(set) var loadingNode: XRayNode?
    @Published private(set) var hasFullDiskAccess = PermissionsHelper.hasFullDiskAccessCached()
    @Published var errorMessage: String?

    /// Visão da pasta atual: hierarquia (pastas e arquivos diretos) ou os
    /// maiores arquivos de toda a subárvore — o atalho do macro para o micro.
    enum Mode: String, CaseIterable, Identifiable {
        case folders = "Folders"
        case largestFiles = "Largest files"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .folders {
        didSet { if mode == .largestFiles { loadLargestFiles() } else { cancelLargestFiles() } }
    }

    @Published private(set) var largestFiles: [XRayNode] = []
    @Published private(set) var isFindingLargestFiles = false
    private var largestFilesTask: Task<Void, Never>?
    private var largestFilesCancelled: CancelFlag?

    /// Profundidade da passada inicial a partir do volume Data
    /// (Data/Users/eu/Library/Application Support/App = 5). Abaixo disso, abrir
    /// uma pasta mede só aquele ramo.
    static let initialDepth = 6
    static let drillDepth = 3
    /// Ao abrir uma pasta, todos os arquivos aparecem um a um; só acima deste
    /// número o resto (os menores) vira uma linha agregada.
    static let maxListedFiles = 5000
    /// Quantos itens a visão "Largest files" mostra.
    static let largestFilesLimit = 300

    private let service = DiskXRayService.shared
    private let firmlinks = Firmlinks.system()
    private var scanTask: Task<Void, Never>?
    /// Pastas cujos arquivos já foram listados (evita duplicar ao reabrir).
    private var filesLoaded = Set<ObjectIdentifier>()

    // MARK: - Scan

    func startScan() {
        scanTask?.cancel()
        isScanning = true
        measuredBytes = 0
        currentPath = ""
        scanStarted = Date()
        errorMessage = nil
        hasFullDiskAccess = PermissionsHelper.hasFullDiskAccess()

        scanTask = Task { [weak self] in
            guard let self else { return }
            let service = self.service
            overview = await runBlocking { service.overview() }

            let measurement = await service.measure(root: DiskXRayService.dataRoot, depth: Self.initialDepth) { bytes, path in
                Task { @MainActor [weak self] in
                    self?.measuredBytes = bytes
                    self?.currentPath = path
                }
            }
            guard !measurement.cancelled else {
                isScanning = false
                return
            }

            let tree = DuOutput.buildTree(
                root: DiskXRayService.dataRoot,
                sizes: measurement.sizes,
                unreadable: measurement.unreadable,
                maxDepth: Self.initialDepth,
                displayPath: firmlinks.displayPath
            )
            guard let tree else {
                errorMessage = "Could not measure the data volume."
                isScanning = false
                return
            }
            tree.setChildren((tree.children ?? []) + unmeasuredNode(for: tree))
            filesLoaded = [ObjectIdentifier(tree)]
            root = tree
            current = tree
            breadcrumbs = [tree]
            selected = nil
            mode = .folders
            isScanning = false
            load(tree) // arquivos soltos na raiz do volume
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    /// Fecha a conta: o que o APFS diz que o volume Data ocupa menos o que o
    /// `du` conseguiu ler vira uma linha explícita, em vez de sumir.
    private func unmeasuredNode(for tree: XRayNode) -> [XRayNode] {
        guard let data = overview?.dataVolume else { return [] }
        let gap = data.bytes - tree.size
        // Abaixo de 100 MB é ruído de arredondamento/metadados.
        guard gap > 100 * 1024 * 1024 else { return [] }
        let node = XRayNode(
            path: tree.path, displayPath: tree.displayPath,
            name: "Not measured", kind: .unmeasured, size: gap
        )
        tree.size += gap
        return [node]
    }

    /// Texto que explica a linha "Not measured".
    var unmeasuredExplanation: String {
        hasFullDiskAccess
            ? "Space the data volume uses that no folder accounts for: areas only root can read " +
            "(Spotlight index, document versions, system databases) and APFS metadata."
            : "Space the data volume uses that MAC-LIMPO could not read. Grant Full Disk Access to " +
            "measure protected folders (Mail, Messages, Safari, app containers) — the rest is areas only " +
            "root can read and APFS metadata."
    }

    // MARK: - Navegação

    func open(_ node: XRayNode) {
        guard node.isNavigable else { return }
        selected = nil
        if mode == .largestFiles { mode = .folders }
        if node.children == nil || !filesLoaded.contains(ObjectIdentifier(node)) {
            filesLoaded.insert(ObjectIdentifier(node))
            load(node)
        }
        current = node
        if let index = breadcrumbs.firstIndex(where: { $0 === node }) {
            breadcrumbs = Array(breadcrumbs.prefix(through: index))
        } else {
            breadcrumbs = path(to: node)
        }
    }

    func goUp() {
        guard breadcrumbs.count > 1 else { return }
        open(breadcrumbs[breadcrumbs.count - 2])
    }

    private func path(to node: XRayNode) -> [XRayNode] {
        var chain: [XRayNode] = []
        var cursor: XRayNode? = node
        while let item = cursor {
            chain.insert(item, at: 0)
            cursor = item.parent
        }
        return chain
    }

    /// Mede um ramo além da passada inicial e/ou troca "arquivos soltos" pelos
    /// arquivos reais da pasta (os grandes um a um, o resto agregado).
    private func load(_ node: XRayNode) {
        loadingNode = node
        let service = service
        let path = node.path
        let needsMeasure = node.children == nil
        Task {
            var subtree: XRayNode?
            if needsMeasure {
                let measurement = await service.measure(root: path, depth: Self.drillDepth) { _, _ in }
                subtree = DuOutput.buildTree(
                    root: path, sizes: measurement.sizes, unreadable: measurement.unreadable,
                    maxDepth: Self.drillDepth, displayPath: firmlinks.displayPath
                )
            }
            let files = await runBlocking { service.files(in: path) }

            if let subtree {
                node.isPartial = node.isPartial || subtree.isPartial
                node.setChildren(subtree.children ?? [])
            }
            replaceLooseFiles(of: node, with: files)
            if loadingNode === node { loadingNode = nil }
            objectWillChange.send()
        }
    }

    private func replaceLooseFiles(of node: XRayNode, with files: [(name: String, path: String, size: Int64)]) {
        guard var children = node.children,
              let looseIndex = children.firstIndex(where: { $0.kind == .looseFiles })
        else { return }
        let loose = children.remove(at: looseIndex)

        let big = Array(files.sorted { $0.size > $1.size }.prefix(Self.maxListedFiles))
        var fileNodes = big.map { file in
            XRayNode(
                path: file.path, displayPath: firmlinks.displayPath(file.path),
                name: file.name, kind: .file, size: file.size
            )
        }
        let rest = loose.size - fileNodes.reduce(0) { $0 + $1.size }
        if rest > 0 {
            let smallCount = files.count - big.count
            fileNodes.append(XRayNode(
                path: node.path, displayPath: node.displayPath,
                name: smallCount > 0 ? "\(smallCount) smaller files" : "Unlisted files",
                kind: .looseFiles, size: rest
            ))
        }
        node.setChildren(children + fileNodes)
    }

    // MARK: - Maiores arquivos

    private func loadLargestFiles() {
        guard let folder = current else { return }
        cancelLargestFiles()
        largestFiles = []
        isFindingLargestFiles = true
        let flag = CancelFlag()
        largestFilesCancelled = flag
        let path = folder.path
        let limit = Self.largestFilesLimit
        largestFilesTask = Task {
            let found = await runBlocking {
                DiskXRayService.shared.largestFiles(under: path, limit: limit, isCancelled: { flag.isSet })
            }
            guard !flag.isSet else { return }
            largestFiles = found.map { file in
                let node = XRayNode(
                    path: file.path, displayPath: firmlinks.displayPath(file.path),
                    name: file.name, kind: .file, size: file.size
                )
                node.parent = folder
                return node
            }
            isFindingLargestFiles = false
        }
    }

    private func cancelLargestFiles() {
        largestFilesCancelled?.set()
        largestFilesTask?.cancel()
        isFindingLargestFiles = false
    }

    /// Caminho do arquivo relativo à pasta atual, para a visão "Largest files".
    func relativeLocation(of node: XRayNode) -> String {
        guard let base = current?.displayPath else { return node.displayPath }
        let folder = (node.displayPath as NSString).deletingLastPathComponent
        guard folder.hasPrefix(base) else { return folder }
        let relative = folder.dropFirst(base.count).drop { $0 == "/" }
        return relative.isEmpty ? "in this folder" : String(relative)
    }

    // MARK: - Ações

    func revealInFinder(_ node: XRayNode) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.displayPath)])
    }

    /// Pré-visualização do Quick Look, a mesma da barra de espaço no Finder.
    func quickLook(_ node: XRayNode) {
        let path = node.displayPath
        Task.detached {
            _ = ShellExecutor.shared.run("/usr/bin/qlmanage", ["-p", path], timeout: 600)
        }
    }

    func openWithDefaultApp(_ node: XRayNode) {
        NSWorkspace.shared.open(URL(fileURLWithPath: node.displayPath))
    }

    func copyPath(_ node: XRayNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.displayPath, forType: .string)
    }

    func canTrash(_ node: XRayNode) -> Bool {
        (node.kind == .directory || node.kind == .file) && XRayHints.canTrash(displayPath: node.displayPath)
    }

    func moveToTrash(_ node: XRayNode) {
        guard canTrash(node), let parent = node.parent else { return }
        let path = node.displayPath
        Task {
            let ok = await runBlocking { DiskXRayService.shared.trash(path: path) }
            if ok {
                largestFiles.removeAll { $0 === node }
                parent.remove(node)
                if selected === node { selected = nil }
                objectWillChange.send()
            } else {
                errorMessage = "Could not move \(node.name) to the Trash."
            }
        }
    }

    func openFullDiskAccessSettings() {
        PermissionsHelper.openFullDiskAccessSettings()
    }

    func hint(for node: XRayNode) -> XRayHint? {
        guard node.kind == .directory || node.kind == .file else { return nil }
        return XRayHints.hint(forDisplayPath: node.displayPath)
    }
}

/// Sinal de cancelamento para trabalho bloqueante fora do pool cooperativo.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
