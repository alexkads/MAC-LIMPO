// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Estado do Disk X-Ray: varredura, árvore de pastas, tipos de arquivo e mapa.
@MainActor
final class DiskXRayViewModel: ObservableObject {
    // MARK: - Varredura

    @Published private(set) var overview: DiskOverview?
    @Published private(set) var index: DiskScanIndex?
    @Published private(set) var scanRoot = DiskXRayService.dataRoot
    @Published private(set) var isScanning = false
    @Published private(set) var progress: DiskScanner.Progress?
    @Published private(set) var scanStarted: Date?
    @Published private(set) var scanDuration: TimeInterval?
    @Published var errorMessage: String?
    private var scanCancel: CancelFlag?
    private let firmlinks = Firmlinks.system()
    private var volumeName = "Macintosh HD"

    /// O volume inteiro, não uma pasta: só ele tem espaço livre e o "resto do sistema".
    var isDriveScan: Bool { scanRoot == DiskXRayService.dataRoot }

    // MARK: - Opções

    @Published var showFreeSpace = false { didSet { structureChanged() } }
    @Published var showUnaccounted = false { didSet { structureChanged() } }
    /// Tamanho lógico (o que os arquivos dizem ter) em vez do espaço ocupado.
    @Published var useLogicalSize = false { didSet { structureChanged() } }
    static let largestFileCount = 100

    // MARK: - Itens sintéticos

    static let unaccountedItem: Int32 = -2
    static let freeSpaceItem: Int32 = -3

    // MARK: - Árvore de pastas

    enum TreeColumn: Int, CaseIterable, Identifiable {
        case name, size, share, files, folders, logicalSize, modified

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .name: "Name"
            case .size: "Size"
            case .share: "Share"
            case .files: "Files"
            case .folders: "Folders"
            case .logicalSize: "Logical Size"
            case .modified: "Modified"
            }
        }

        var width: CGFloat {
            switch self {
            case .name: 280
            case .share: 140
            case .modified: 150
            case .size, .logicalSize: 84
            case .files, .folders: 74
            }
        }

        var alignLeft: Bool { self == .name || self == .modified || self == .share }
        var isRequired: Bool { self == .name || self == .size }
        var ascendingByDefault: Bool { self == .name }
    }

    @Published var visibleColumns: Set<TreeColumn> = [.name, .size, .share, .files, .modified]
    @Published private(set) var sortColumn: TreeColumn = .size
    @Published private(set) var sortAscending = false

    @Published private(set) var selected: Int32?
    /// Incrementado quando a seleção deve aparecer na árvore (expandir e rolar).
    @Published private(set) var revealToken = 0
    /// Incrementado quando a estrutura ou a ordem da árvore muda.
    @Published private(set) var treeVersion = 0
    private var sortedChildren: [Int32: [Int32]] = [:]

    enum Tab: String, CaseIterable, Identifiable {
        case folders = "Folders"
        case largestFiles = "Largest Files"
        var id: String { rawValue }
    }

    @Published var tab: Tab = .folders
    @Published private(set) var largestFiles: [Int32] = []

    // MARK: - Tipos de arquivo

    struct CategoryStats: Identifiable {
        let category: FileCategory
        var bytes: Int64 = 0
        var files: Int = 0
        var extensions: [Int32] = []
        var id: Int { category.rawValue }
    }

    enum TypeFilter: Equatable, Sendable {
        case category(FileCategory)
        case fileExtension(Int32)
    }

    @Published private(set) var categories: [CategoryStats] = []
    /// Tipo em destaque no mapa (o resto esmaece).
    @Published private(set) var typeFilter: TypeFilter?
    private var extensionCategory: [FileCategory] = []
    private var descriptions: [String: String] = [:]
    private var fileIcons: [String: NSImage] = [:]

    // MARK: - Mapa

    @Published private(set) var zoomItem: Int32 = 0
    @Published private(set) var rendering: TreemapRenderer.Rendering?
    @Published private(set) var isRendering = false
    private var reselectStack: [Int32] = []
    private var treemapSize: (width: Int, height: Int, scale: CGFloat) = (0, 0, 2)
    private var renderTask: Task<Void, Never>?
    private var renderCancel: CancelFlag?
    var treemapBackground = TreemapRenderer.RGB(r: 0.12, g: 0.12, b: 0.13)
    var treemapDark = true

    var isZoomed: Bool { index != nil && zoomItem != index?.root }

    // MARK: - Scan

    /// Raiz do primeiro scan: o volume de dados, ou MACLIMPO_XRAY_ROOT
    /// (desenvolvimento: capturas de tela de uma pasta de demonstração).
    static var initialRoot: String {
        ProcessInfo.processInfo.environment["MACLIMPO_XRAY_ROOT"] ?? DiskXRayService.dataRoot
    }

    func startScan(root: String = DiskXRayViewModel.initialRoot) {
        scanCancel?.set()
        renderCancel?.set()
        let cancel = CancelFlag()
        scanCancel = cancel

        scanRoot = root
        isScanning = true
        progress = nil
        scanStarted = Date()
        scanDuration = nil
        errorMessage = nil
        index = nil
        rendering = nil
        selected = nil
        typeFilter = nil
        largestFiles = []
        categories = []
        sortedChildren = [:]
        reselectStack = []

        Task { [weak self] in
            let overview = await runBlocking { DiskXRayService.shared.overview() }
            guard let self, !cancel.isSet else { return }
            self.overview = overview
            let started = Date()
            let scanned = await runBlocking {
                DiskScanner.scan(root: root, isCancelled: { cancel.isSet }) { [weak self] progress in
                    Task { @MainActor in
                        guard !cancel.isSet else { return }
                        self?.progress = progress
                    }
                }
            }
            guard !cancel.isSet else { return }
            isScanning = false
            guard let scanned else {
                errorMessage = "Could not read \(firmlinks.displayPath(root))."
                return
            }
            scanDuration = Date().timeIntervalSince(started)
            volumeName = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]))?
                .volumeLocalizedName ?? "Macintosh HD"
            index = scanned
            zoomItem = scanned.root
            buildCategories()
            refreshLargestFiles()
            treeVersion += 1
            select(scanned.root, reveal: false)
            scheduleRender()

            // Desenvolvimento: estado de demonstração para capturas de tela.
            let environment = ProcessInfo.processInfo.environment
            if environment["MACLIMPO_XRAY_LOGICAL"] == "1" { useLogicalSize = true }
            if environment["MACLIMPO_XRAY_DEMO"] == "1" {
                showUnaccounted = true
                showFreeSpace = true
                if let biggest = largestFiles.first { select(biggest) }
            }
        }
    }

    func cancelScan() {
        scanCancel?.set()
        isScanning = false
    }

    func chooseFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startScan(root: url.path)
    }

    private func structureChanged() {
        sortedChildren = [:]
        if let selected, selected < 0, !isPseudoVisible(selected) { self.selected = index?.root }
        buildCategories()
        refreshLargestFiles()
        treeVersion += 1
        scheduleRender()
    }

    // MARK: - Tamanhos

    private func isPseudoVisible(_ item: Int32) -> Bool {
        switch item {
        case Self.unaccountedItem: isDriveScan && showUnaccounted
        case Self.freeSpaceItem: isDriveScan && showFreeSpace
        default: true
        }
    }

    var freeSpaceBytes: Int64 { overview?.free ?? 0 }

    /// O que o disco tem em uso e a leitura não alcançou: macOS (volume do
    /// sistema), Preboot, swap e áreas protegidas.
    var unaccountedBytes: Int64 {
        guard let overview, let index else { return 0 }
        return max(0, overview.used - index.physical[0])
    }

    var scannedBytes: Int64 {
        guard let index else { return 0 }
        return useLogicalSize ? index.logical[0] : index.physical[0]
    }

    func size(_ item: Int32) -> Int64 {
        switch item {
        case Self.unaccountedItem: return unaccountedBytes
        case Self.freeSpaceItem: return freeSpaceBytes
        default:
            guard let index else { return 0 }
            var value = useLogicalSize ? index.logical[Int(item)] : index.physical[Int(item)]
            if item == index.root, isDriveScan {
                if showUnaccounted { value += unaccountedBytes }
                if showFreeSpace { value += freeSpaceBytes }
            }
            return value
        }
    }

    func parent(_ item: Int32) -> Int32? {
        guard let index else { return nil }
        if item < 0 { return index.root }
        return item == index.root ? nil : index.parent[Int(item)]
    }

    func fractionOfParent(_ item: Int32) -> Double {
        guard let parent = parent(item) else { return 1 }
        let total = size(parent)
        return total > 0 ? Double(size(item)) / Double(total) : 0
    }

    // MARK: - Texto das colunas

    func name(_ item: Int32) -> String {
        switch item {
        case Self.unaccountedItem: return "System & Unaccounted"
        case Self.freeSpaceItem: return "Free Space"
        default:
            guard let index else { return "" }
            guard item == index.root else { return index.name(item) }
            return isDriveScan ? volumeName : firmlinks.displayPath(index.rootPath)
        }
    }

    func path(_ item: Int32) -> String {
        guard let index, item >= 0 else { return "" }
        return firmlinks.displayPath(index.path(item))
    }

    func text(_ column: TreeColumn, _ item: Int32) -> String {
        guard let index else { return "" }
        let isPseudo = item < 0
        switch column {
        case .name: return name(item)
        case .size: return SizeFormat.bytes(size(item))
        case .share: return SizeFormat.percent(fractionOfParent(item))
        case .files:
            guard !isPseudo, index.isDirectory(item) else { return "" }
            return SizeFormat.count(Int(index.fileCount[Int(item)]))
        case .folders:
            guard !isPseudo, index.isDirectory(item) else { return "" }
            return SizeFormat.count(Int(index.folderCount[Int(item)]))
        case .logicalSize:
            guard !isPseudo else { return "" }
            return SizeFormat.bytes(index.logical[Int(item)])
        case .modified:
            guard !isPseudo else { return "" }
            return SizeFormat.date(index.modified[Int(item)])
        }
    }

    func isDirectory(_ item: Int32) -> Bool {
        guard let index, item >= 0 else { return false }
        return index.isDirectory(item)
    }

    func icon(_ item: Int32) -> NSImage? {
        guard let index, item >= 0, !index.isDirectory(item) else { return nil }
        return extensionIcon(index.extensionIndex[Int(item)])
    }

    // MARK: - Árvore: filhos e ordenação

    func hasChildren(_ item: Int32) -> Bool {
        guard let index, item >= 0 else { return false }
        if item == index.root, isDriveScan, showUnaccounted || showFreeSpace { return true }
        return index.isDirectory(item) && index.hasChildren(item)
    }

    func treeChildren(_ item: Int32) -> [Int32] {
        if let cached = sortedChildren[item] { return cached }
        guard let index, item >= 0 else { return [] }
        var kids = index.children(item)
        if item == index.root, isDriveScan {
            if showFreeSpace { kids.append(Self.freeSpaceItem) }
            if showUnaccounted { kids.append(Self.unaccountedItem) }
        }
        kids.sort { compare($0, $1) }
        sortedChildren[item] = kids
        return kids
    }

    private func compare(_ a: Int32, _ b: Int32) -> Bool {
        func ordered<T: Comparable>(_ x: T, _ y: T) -> Bool? {
            x == y ? nil : (sortAscending ? x < y : x > y)
        }
        let primary: Bool? = switch sortColumn {
        case .name: ordered(name(a).lowercased(), name(b).lowercased())
        case .size, .share: ordered(size(a), size(b))
        case .files: ordered(countValue(a, files: true), countValue(b, files: true))
        case .folders: ordered(countValue(a, files: false), countValue(b, files: false))
        case .logicalSize: ordered(a >= 0 ? index?.logical[Int(a)] ?? 0 : 0, b >= 0 ? index?.logical[Int(b)] ?? 0 : 0)
        case .modified: ordered(a >= 0 ? index?.modified[Int(a)] ?? 0 : 0, b >= 0 ? index?.modified[Int(b)] ?? 0 : 0)
        }
        return primary ?? (size(a) > size(b))
    }

    private func countValue(_ item: Int32, files: Bool) -> Int32 {
        guard let index, item >= 0 else { return 0 }
        return files ? index.fileCount[Int(item)] : index.folderCount[Int(item)]
    }

    func setTreeSort(_ column: TreeColumn, ascending: Bool) {
        guard column != sortColumn || ascending != sortAscending else { return }
        sortColumn = column
        sortAscending = ascending
        sortedChildren = [:]
        treeVersion += 1
    }

    func toggleColumn(_ column: TreeColumn) {
        guard !column.isRequired else { return }
        if visibleColumns.contains(column) { visibleColumns.remove(column) } else { visibleColumns.insert(column) }
    }

    // MARK: - Seleção

    func select(_ item: Int32, reveal: Bool = true) {
        guard selected != item || reveal else { return }
        selected = item
        if reveal { revealToken += 1 }
    }

    func lineage(_ item: Int32) -> [Int32] {
        guard let index else { return [] }
        if item < 0 { return [index.root, item] }
        return index.lineage(item)
    }

    // MARK: - Maiores arquivos

    private func refreshLargestFiles() {
        guard let index else { return }
        largestFiles = index.largestFiles(in: index.root, limit: Self.largestFileCount, logicalSize: useLogicalSize)
    }

    func location(of item: Int32) -> String {
        (path(item) as NSString).deletingLastPathComponent
    }

    // MARK: - Tipos de arquivo

    private func buildCategories() {
        guard let index else { return }
        extensionCategory = index.extensions.map(FileCategory.of(extensionKey:))
        let logical = useLogicalSize
        let bytes: (Int) -> Int64 = { logical ? index.extensionLogical[$0] : index.extensionPhysical[$0] }
        var stats = Dictionary(uniqueKeysWithValues: FileCategory.allCases.map { ($0, CategoryStats(category: $0)) })
        for ext in index.extensions.indices where index.extensionFiles[ext] > 0 {
            let category = extensionCategory[ext]
            stats[category]?.bytes += bytes(ext)
            stats[category]?.files += Int(index.extensionFiles[ext])
            stats[category]?.extensions.append(Int32(ext))
        }
        categories = stats.values
            .filter { $0.files > 0 }
            .map { stat in
                var sorted = stat
                sorted.extensions.sort { bytes(Int($0)) > bytes(Int($1)) }
                return sorted
            }
            .sorted { $0.bytes > $1.bytes }
    }

    func category(ofExtension ext: Int32) -> FileCategory {
        Int(ext) < extensionCategory.count && ext >= 0 ? extensionCategory[Int(ext)] : .other
    }

    func extensionName(_ ext: Int32) -> String {
        let key = index?.extensions[Int(ext)] ?? ""
        return key.isEmpty ? "No extension" : key
    }

    func extensionBytes(_ ext: Int32) -> Int64 {
        guard let index else { return 0 }
        return useLogicalSize ? index.extensionLogical[Int(ext)] : index.extensionPhysical[Int(ext)]
    }

    func extensionFiles(_ ext: Int32) -> Int { Int(index?.extensionFiles[Int(ext)] ?? 0) }

    func extensionDescription(_ ext: Int32) -> String {
        let key = index?.extensions[Int(ext)] ?? ""
        guard !key.isEmpty else { return "Files without an extension" }
        if let cached = descriptions[key] { return cached }
        let bare = String(key.dropFirst())
        let text = UTType(filenameExtension: bare)?.localizedDescription ?? "\(bare.uppercased()) file"
        descriptions[key] = text
        return text
    }

    func extensionIcon(_ ext: Int32) -> NSImage {
        let key = ext >= 0 ? index?.extensions[Int(ext)] ?? "" : ""
        if let cached = fileIcons[key] { return cached }
        let type = key.count > 1 ? (UTType(filenameExtension: String(key.dropFirst())) ?? .data) : .data
        let image = NSWorkspace.shared.icon(for: type)
        fileIcons[key] = image
        return image
    }

    func setTypeFilter(_ filter: TypeFilter?) {
        typeFilter = filter == typeFilter ? nil : filter
        scheduleRender()
    }

    // MARK: - Mapa

    private func treemapChildren(_ item: Int32) -> [Int32] {
        guard let index, item >= 0 else { return [] }
        var kids = index.children(item)
        if item == index.root, isDriveScan {
            if showFreeSpace { kids.append(Self.freeSpaceItem) }
            if showUnaccounted { kids.append(Self.unaccountedItem) }
        }
        if useLogicalSize || item == index.root { kids.sort { size($0) > size($1) } }
        return kids
    }

    /// Fonte para o renderizador, com tudo capturado por valor (roda fora do MainActor).
    private func renderSource() -> TreemapRenderer.Source? {
        guard let index else { return nil }
        let logical = useLogicalSize
        let pseudo: [Int32: Int64] = [Self.freeSpaceItem: freeSpaceBytes, Self.unaccountedItem: unaccountedBytes]
        let rootChildren = treemapChildren(index.root)
        let categories = extensionCategory
        let filter = typeFilter
        let names: [Int32: String] = [
            Self.freeSpaceItem: name(Self.freeSpaceItem), Self.unaccountedItem: name(Self.unaccountedItem),
            index.root: name(index.root)
        ]
        let categoryOf: @Sendable (Int32) -> FileCategory = { item in
            let ext = index.extensionIndex[Int(item)]
            return ext >= 0 && Int(ext) < categories.count ? categories[Int(ext)] : .other
        }
        let weight: @Sendable (Int32) -> UInt64 = { item in
            if item < 0 { return UInt64(max(0, pseudo[item] ?? 0)) }
            return UInt64(max(0, logical ? index.logical[Int(item)] : index.physical[Int(item)]))
        }
        return TreemapRenderer.Source(
            weight: weight,
            children: { item in
                if item == index.root { return rootChildren }
                guard item >= 0 else { return [] }
                var kids = index.children(item)
                if logical { kids.sort { index.logical[Int($0)] > index.logical[Int($1)] } }
                return kids
            },
            isLeaf: { item in item < 0 || !index.isDirectory(item) || !index.hasChildren(item) },
            color: { item in
                switch item {
                case Self.freeSpaceItem: return TreemapRenderer.RGB(r: 0.55, g: 0.78, b: 0.62)
                case Self.unaccountedItem: return TreemapRenderer.RGB(r: 0.86, g: 0.64, b: 0.28)
                default:
                    guard !index.isDirectory(item) else { return TreemapRenderer.RGB(r: 0.5, g: 0.5, b: 0.55) }
                    let rgb = categoryOf(item).rgb
                    return TreemapRenderer.RGB(r: rgb.r, g: rgb.g, b: rgb.b)
                }
            },
            name: { item in names[item] ?? index.name(item) },
            sizeText: { item in SizeFormat.bytes(Int64(weight(item))) },
            isEmphasized: { item in
                guard let filter else { return true }
                guard item >= 0, !index.isDirectory(item) else { return false }
                switch filter {
                case let .fileExtension(selected): return index.extensionIndex[Int(item)] == selected
                case let .category(category): return categoryOf(item) == category
                }
            }
        )
    }

    func treemapResized(width: Int, height: Int, scale: CGFloat) {
        guard width != treemapSize.width || height != treemapSize.height || scale != treemapSize.scale else { return }
        treemapSize = (width, height, scale)
        scheduleRender(debounce: true)
    }

    func scheduleRender(debounce: Bool = false) {
        guard index != nil, treemapSize.width > 0, treemapSize.height > 0, let source = renderSource() else { return }
        renderCancel?.set()
        let cancel = CancelFlag()
        renderCancel = cancel
        let previous = renderTask
        let root = zoomItem
        let (width, height, scale) = treemapSize
        let style = TreemapRenderer.Style(scale: scale, dark: treemapDark, background: treemapBackground)
        isRendering = true

        renderTask = Task {
            await previous?.value
            if debounce { try? await Task.sleep(for: .milliseconds(120)) }
            guard !cancel.isSet else { return }
            let result = await runBlocking {
                TreemapRenderer.render(root: root, width: width, height: height, style: style, source: source,
                                       isCancelled: { cancel.isSet })
            }
            guard !cancel.isSet else { return }
            rendering = result
            isRendering = false
        }
    }

    func item(atPixel point: CGPoint) -> Int32? {
        guard let rendering, let source = renderSource() else { return nil }
        return TreemapRenderer.hitTest(point, in: rendering, source: source)
    }

    func clickTreemap(atPixel point: CGPoint) {
        guard let item = item(atPixel: point) else { return }
        tab = .folders
        reselectStack = []
        select(item)
    }

    /// Duplo clique: entra na pasta (de um arquivo, entra na pasta dele).
    func doubleClickTreemap(atPixel point: CGPoint) {
        guard let item = item(atPixel: point) else { return }
        select(item)
        zoom(into: item)
    }

    var canZoomIn: Bool { selected != nil && index != nil }

    func zoomIn() {
        guard let selected else { return }
        zoom(into: selected)
    }

    func zoom(into item: Int32) {
        guard let index else { return }
        var target = item
        if target < 0 || !index.isDirectory(target) { target = parent(target) ?? index.root }
        guard target != zoomItem else { return }
        zoomItem = target
        scheduleRender()
    }

    func zoomOut() {
        guard let index, zoomItem != index.root else { return }
        zoomItem = parent(zoomItem) ?? index.root
        scheduleRender()
    }

    func zoomReset() {
        guard let index, zoomItem != index.root else { return }
        zoomItem = index.root
        scheduleRender()
    }

    /// Trilha da raiz até o item em zoom.
    var breadcrumbs: [Int32] { lineage(zoomItem) }

    func selectParent() {
        guard let selected, let parent = parent(selected) else { return }
        reselectStack.append(selected)
        select(parent)
    }

    func reselectChild() {
        guard let child = reselectStack.popLast() else { return }
        select(child)
    }

    // MARK: - Barra de status

    func statusText(hovered: Int32?) -> String {
        guard let item = hovered ?? selected else { return isScanning ? "Scanning…" : "Ready" }
        return item >= 0 ? path(item) : name(item)
    }

    func statusSize(hovered: Int32?) -> String {
        guard let item = hovered ?? selected else { return "" }
        return SizeFormat.bytes(size(item))
    }

    // MARK: - Ações

    func open(_ item: Int32) {
        guard item >= 0 else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path(item)))
    }

    func revealInFinder(_ item: Int32) {
        guard item >= 0 else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path(item))])
    }

    func quickLook(_ item: Int32) {
        guard item >= 0 else { return }
        let target = path(item)
        Task.detached {
            _ = ShellExecutor.shared.run("/usr/bin/qlmanage", ["-p", target], timeout: 600)
        }
    }

    func copyPath(_ item: Int32) {
        guard item >= 0 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path(item), forType: .string)
    }

    /// Nunca a raiz do scan nem a home e suas pastas-base; o resto depende da
    /// permissão do usuário no arquivo.
    func canTrash(_ item: Int32) -> Bool {
        guard let index, item >= 0, item != index.root else { return false }
        let target = path(item)
        let home = NSHomeDirectory()
        guard target != home else { return false }
        if (target as NSString).deletingLastPathComponent == home,
           Self.protectedHomeFolders.contains((target as NSString).lastPathComponent) {
            return false
        }
        return FileManager.default.isDeletableFile(atPath: target)
    }

    private static let protectedHomeFolders: Set<String> = [
        "Library", "Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies", "Public", "Applications"
    ]

    func moveToTrash(_ item: Int32) {
        guard canTrash(item), let index else { return }
        let target = path(item)
        Task {
            let ok = await runBlocking { DiskXRayService.shared.trash(path: target) }
            guard ok else {
                errorMessage = "Could not move \(index.name(item)) to the Trash."
                return
            }
            renderCancel?.set()
            await renderTask?.value
            index.remove(item)
            if let selected, selected >= 0, selected == item || index.isAncestor(item, of: selected) {
                self.selected = index.parent[Int(item)]
            }
            if zoomItem == item || index.isAncestor(item, of: zoomItem) { zoomItem = index.parent[Int(item)] }
            sortedChildren = [:]
            buildCategories()
            refreshLargestFiles()
            treeVersion += 1
            scheduleRender()
        }
    }

    func openFullDiskAccessSettings() {
        PermissionsHelper.openFullDiskAccessSettings()
    }
}

/// Sinal de cancelamento para trabalho bloqueante fora do pool cooperativo.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
