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
    /// Mapa em 3D (Metal, relevo de almofadas) ou 2D (CoreGraphics, como sempre
    /// foi). Lembrado entre aberturas.
    @Published var map3D = UserDefaults.standard.bool(forKey: "DiskXRayMap3D") {
        didSet {
            UserDefaults.standard.set(map3D, forKey: "DiskXRayMap3D")
            scheduleRender()
        }
    }
    /// Nomes nos blocos e faixas das pastas (2D e 3D); desligado, o mapa fica
    /// limpo e o nome aparece só no tooltip. Lembrado entre aberturas.
    @Published var showLabels = UserDefaults.standard.object(forKey: "DiskXRayLabels") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showLabels, forKey: "DiskXRayLabels")
            scheduleRender()
        }
    }
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
    /// Camada mais recente: hit-test, contornos e a parte mais nítida do mapa.
    @Published private(set) var rendering: TreemapRenderer.Rendering?
    /// Como num jogo de mapa, nada fica vazio ao arrastar ou afastar: por baixo da
    /// camada atual ficam o mapa inteiro (`baseLayer`) e as últimas camadas da
    /// mesma geração, esticadas até o redesenho chegar.
    @Published private(set) var baseLayer: TreemapRenderer.Rendering?
    @Published private(set) var backdrop: [TreemapRenderer.Rendering] = []
    @Published private(set) var isRendering = false
    /// Muda quando o mapa muda de verdade (pasta, tamanho, filtros, cores); mexer
    /// só no viewport mantém a geração e as camadas antigas continuam válidas.
    private var renderGeneration = 0
    private var layersGeneration = -1
    private var renderBusy = false
    private var renderPending = false
    private var reselectStack: [Int32] = []
    private var treemapSize: (width: Int, height: Int, scale: CGFloat) = (0, 0, 2)
    private var renderTask: Task<Void, Never>?
    private var renderCancel: CancelFlag?
    var treemapBackground = TreemapRenderer.RGB(r: 0.12, g: 0.12, b: 0.13)
    var treemapDark = true

    var isZoomed: Bool { index != nil && zoomItem != index?.root }

    /// Lupa (pinça): parte visível do mapa em coordenadas unitárias, quadrada no
    /// espaço unitário (lado = 1 / ampliação). Independe do tamanho da janela.
    @Published private(set) var viewport = TreemapRenderer.fullViewport
    /// Um arquivo de 1 KB num disco de 500 GB pede ~2.000× para ganhar bloco com
    /// rótulo; o teto cobre discos de vários TB. Em Double o layout segue exato.
    static let maxMagnification: CGFloat = 100_000_000
    var magnification: CGFloat { 1 / viewport.width }
    var isMagnified: Bool { viewport.width < 0.999 }

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
        baseLayer = nil
        backdrop = []
        selected = nil
        typeFilter = nil
        largestFiles = []
        categories = []
        sortedChildren = [:]
        reselectStack = []

        // Fora da Task: dentro dela `self` já foi desembrulhado por `guard let self`,
        // e um `[weak self]` aninhado ali diverge da captura forte implícita.
        let onProgress: @Sendable (DiskScanner.Progress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard !cancel.isSet else { return }
                self?.progress = progress
            }
        }

        Task { [weak self] in
            let overview = await runBlocking { DiskXRayService.shared.overview() }
            guard let self, !cancel.isSet else { return }
            self.overview = overview
            let started = Date()
            let scanned = await runBlocking {
                DiskScanner.scan(root: root, isCancelled: { cancel.isSet }, progress: onProgress)
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
            viewport = TreemapRenderer.fullViewport
            buildCategories()
            refreshLargestFiles()
            treeVersion += 1
            select(scanned.root, reveal: false)
            scheduleRender()

            // Desenvolvimento: estado de demonstração para capturas de tela.
            let environment = ProcessInfo.processInfo.environment
            if environment["MACLIMPO_XRAY_LOGICAL"] == "1" { useLogicalSize = true }
            if let mode = environment["MACLIMPO_XRAY_3D"] { map3D = mode == "1" }
            if environment["MACLIMPO_XRAY_DEMO"] == "1" {
                showUnaccounted = true
                showFreeSpace = true
                if let biggest = largestFiles.first { select(biggest) }
            }
            if let factor = environment["MACLIMPO_XRAY_MAGNIFY"].flatMap(Double.init) {
                magnify(by: factor, around: CGPoint(x: 0.5, y: 0.5))
            }
            // Seleciona como a árvore faria (o mapa ampliado desliza até ele).
            if let name = environment["MACLIMPO_XRAY_SELECT"],
               let item = (0 ..< Int32(scanned.count)).first(where: { scanned.name($0) == name }) {
                try? await Task.sleep(for: .seconds(1))
                select(item, reveal: false)
            }
            // Seleciona o primeiro item com esse nome e amplia até ele (depois de a
            // árvore carregar, que seleciona a raiz).
            if let name = environment["MACLIMPO_XRAY_FOCUS"],
               let item = (0 ..< Int32(scanned.count)).first(where: { scanned.name($0) == name }) {
                try? await Task.sleep(for: .seconds(1))
                select(item)
                magnifyToSelection()
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

    /// `reveal`: mostra na árvore (seleção vinda do mapa). Sem ele a seleção veio
    /// da árvore ou da lista, e é o mapa que vai até ela.
    func select(_ item: Int32, reveal: Bool = true) {
        guard selected != item || reveal else { return }
        selected = item
        if reveal { revealToken += 1 } else { bringIntoView(item) }
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

    /// O mapa mudou (pasta, tamanho, filtros, cores): nova geração de camadas.
    func scheduleRender(debounce: Bool = false) {
        renderGeneration += 1
        startRender(debounce: debounce)
    }

    /// Só o viewport mudou (pinça, arrasto). Em vez de cancelar e esperar o gesto
    /// parar, deixa o render em curso terminar e já pede o próximo: o mapa vai
    /// ficando nítido durante o movimento.
    private func viewportChanged() {
        if renderBusy {
            renderPending = true
        } else {
            startRender(debounce: false)
        }
    }

    private func startRender(debounce: Bool) {
        guard index != nil, treemapSize.width > 0, treemapSize.height > 0, let source = renderSource() else { return }
        renderCancel?.set()
        let cancel = CancelFlag()
        renderCancel = cancel
        let previous = renderTask
        let root = zoomItem
        let visible = viewport
        let generation = renderGeneration
        let (width, height, scale) = treemapSize
        // Sem Metal (não deve acontecer num Mac atual), o 3D cai para o 2D.
        let style = TreemapRenderer.Style(scale: scale, dark: treemapDark, background: treemapBackground,
                                          cushions: map3D && TreemapMetal.shared != nil, labels: showLabels)
        // Margem além da tela (¼ de cada lado), como os tiles vizinhos de um mapa:
        // ao arrastar, o que entra pela borda já está desenhado.
        let (area, areaWidth, areaHeight) = Self.renderArea(visible: visible, width: width, height: height,
                                                            margin: isMagnified ? 0.25 : 0)
        let needsBase = isMagnified && (baseLayer == nil || layersGeneration != generation)
        isRendering = true
        renderBusy = true
        renderPending = false

        previous?.cancel()
        renderTask = Task {
            await previous?.value
            await render()
            // Substituído por outro pedido: ele cuida do resto.
            guard renderCancel === cancel else { return }
            renderBusy = false
            isRendering = false
            // Cancelado sem substituto (a Lixeira mexendo no índice): não encadeia.
            if renderPending, !cancel.isSet { startRender(debounce: false) }
        }

        func render() async {
            // Sem esta checagem cada pedido cancelado ainda esperava o debounce
            // inteiro, e uma pinça (dezenas de eventos) enfileirava segundos.
            guard !cancel.isSet else { return }
            if debounce { try? await Task.sleep(for: .milliseconds(120)) }
            guard !cancel.isSet else { return }
            let result = await runBlocking {
                TreemapRenderer.render(root: root, width: areaWidth, height: areaHeight, viewport: area, screen: visible,
                                       style: style, source: source, isCancelled: { cancel.isSet })
            }
            guard !cancel.isSet, let result else { return }
            install(result, generation: generation)
            guard needsBase, !cancel.isSet else { return }
            // Base do mapa inteiro, por baixo de tudo, para nunca sobrar borda vazia.
            let base = await runBlocking {
                TreemapRenderer.render(root: root, width: width, height: height, style: style, source: source,
                                       isCancelled: { cancel.isSet })
            }
            if let base, !cancel.isSet, layersGeneration == generation { baseLayer = base }
        }
    }

    /// Área a desenhar (o visível mais `margin` de cada lado, dentro do mapa) e o
    /// tamanho do bitmap. A área é refeita a partir dos pixels inteiros: a escala
    /// fica exatamente a do mapa a 1× vezes a ampliação, nos dois eixos. Só com o
    /// bitmap arredondado, a proporção mudava ~0,1% e, com arquivos de tamanho
    /// idêntico (empates no squarified), a arrumação dos blocos — a caixa da
    /// seleção (`locate`) ficava fora do lugar.
    nonisolated static func renderArea(visible: CGRect, width: Int, height: Int,
                                       margin: CGFloat) -> (area: CGRect, width: Int, height: Int) {
        let pad = visible.width * margin
        let wanted = visible.insetBy(dx: -pad, dy: -pad).intersection(TreemapRenderer.fullViewport)
        let areaWidth = max(1, Int((Double(width) * wanted.width / visible.width).rounded()))
        let areaHeight = max(1, Int((Double(height) * wanted.height / visible.height).rounded()))
        let area = CGRect(origin: wanted.origin,
                          size: CGSize(width: Double(areaWidth) * visible.width / Double(width),
                                       height: Double(areaHeight) * visible.height / Double(height)))
        return (area, areaWidth, areaHeight)
    }

    private func install(_ result: TreemapRenderer.Rendering, generation: Int) {
        if generation != layersGeneration {
            layersGeneration = generation
            backdrop = []
            baseLayer = nil
        } else if let current = rendering, current.viewport != TreemapRenderer.fullViewport {
            // Duas camadas anteriores bastam para a pinça e o arrasto (cada uma
            // tem dezenas de MB).
            backdrop = Array((backdrop + [current]).suffix(2))
        }
        rendering = result
        if result.viewport == TreemapRenderer.fullViewport { baseLayer = result }
    }

    // MARK: - Tooltip 3D

    /// A bandeirinha do item, como tooltip do mapa 3D.
    func flagSprite(for item: Int32, scale: CGFloat, mirrored: Bool = false) -> TreemapFlags.Sprite? {
        guard let index else { return nil }
        return TreemapFlags.sprite(title: name(item), subtitle: SizeFormat.bytes(size(item)),
                                   folder: item >= 0 && index.isDirectory(item), color: flagColor(item), scale: scale,
                                   mirrored: mirrored)
    }

    /// Cor do tipo do arquivo (a faixa junto ao mastro).
    private func flagColor(_ item: Int32) -> TreemapRenderer.RGB {
        guard let index, item >= 0 else { return TreemapRenderer.RGB(r: 0.86, g: 0.64, b: 0.28) }
        let ext = index.extensionIndex[Int(item)]
        let rgb = (ext >= 0 && Int(ext) < extensionCategory.count ? extensionCategory[Int(ext)] : .other).rgb
        return TreemapRenderer.RGB(r: rgb.r, g: rgb.g, b: rgb.b)
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
        viewport = TreemapRenderer.fullViewport
        stopViewportAnimation()
        scheduleRender()
    }

    func zoomOut() {
        guard let index, zoomItem != index.root else { return }
        zoomItem = parent(zoomItem) ?? index.root
        viewport = TreemapRenderer.fullViewport
        stopViewportAnimation()
        scheduleRender()
    }

    func zoomReset() {
        guard let index, zoomItem != index.root else { return }
        zoomItem = index.root
        viewport = TreemapRenderer.fullViewport
        stopViewportAnimation()
        scheduleRender()
    }

    // MARK: - Lupa

    /// Amplia (fator > 1) ou reduz mantendo parado o ponto sob o cursor.
    /// `anchor`: posição na área visível do mapa, em fração (0…1).
    /// `animated`: transição suave (botões e teclado); a pinça segue o dedo.
    func magnify(by factor: CGFloat, around anchor: CGPoint, animated: Bool = false) {
        guard index != nil, factor.isFinite, factor > 0 else { return }
        // Animando, o fator vale sobre o destino (⌘+ repetido acumula).
        let from = viewportAnimation == nil ? viewport : animationTarget
        let side = 1 / min(Self.maxMagnification, max(1, (1 / from.width) * factor))
        let x = from.minX + anchor.x * from.width
        let y = from.minY + anchor.y * from.height
        let target = CGRect(x: x - anchor.x * side, y: y - anchor.y * side, width: side, height: side)
        if animated { animateViewport(to: target) } else { setViewport(target) }
    }

    /// Arrasta o conteúdo; `delta` em fração da área visível (positivo: para a
    /// direita/para baixo, como o dedo no trackpad).
    func pan(by delta: CGSize) {
        guard isMagnified else { return }
        setViewport(viewport.offsetBy(dx: -delta.width * viewport.width, dy: -delta.height * viewport.height))
    }

    func resetMagnification() {
        animateViewport(to: TreemapRenderer.fullViewport)
    }

    /// Toque duplo com dois dedos: alterna entre o mapa inteiro e 4×.
    func toggleMagnification(around anchor: CGPoint) {
        if isMagnified { resetMagnification() } else { magnify(by: 4, around: anchor, animated: true) }
    }

    var canMagnifyToSelection: Bool { index != nil && selected != nil }

    /// Amplia até o item selecionado ocupar boa parte do mapa — chega a um
    /// arquivo de 1 KB no disco inteiro, num voo só (o layout não muda com a
    /// ampliação, então a posição calculada agora é a que vai aparecer).
    func magnifyToSelection() {
        guard let index, let item = selected else { return }
        let inside = item == zoomItem || (item < 0 ? zoomItem == index.root : index.isAncestor(zoomItem, of: item))
        if !inside {
            stopViewportAnimation()
            zoomItem = index.root
            viewport = TreemapRenderer.fullViewport
            scheduleRender()
        } else if item == zoomItem {
            resetMagnification()
            return
        }
        guard let unit = mapAnchor(for: item).flatMap(unitRect) else { return }
        animateViewport(to: TreemapRenderer.viewport(fitting: unit, maxMagnification: Self.maxMagnification))
    }

    /// Selecionado na árvore ou na lista: o mapa vai até ele como o Google Maps
    /// mostra um resultado — sem exagero. Pequeno demais para ler: aproxima até
    /// ocupar ~⅓ da tela, mas no máximo até a pasta dele encher a tela (arquivos
    /// de poucos KB pediriam milhares de ×; o contexto fica e o pino marca o
    /// lugar). Maior que a tela: afasta até caber. Tamanho bom: só desliza, e só
    /// se estiver fora da tela. Um item de 0 KB não tem área: vale a pasta dele.
    private func bringIntoView(_ item: Int32) {
        guard let anchor = mapAnchor(for: item), let unit = unitRect(of: anchor) else { return }
        let current = viewportAnimation == nil ? viewport : animationTarget
        var side = current.width
        if max(unit.width, unit.height) / side < 0.2 {
            var readable = TreemapRenderer.viewport(fitting: unit, fill: 0.35, minThickness: 0.08,
                                                    maxMagnification: Self.maxMagnification).width
            if anchor != zoomItem, let folder = parent(anchor), let folderUnit = unitRect(of: folder) {
                readable = max(readable, TreemapRenderer.viewport(fitting: folderUnit, fill: 0.9, minThickness: 0.3,
                                                                  maxMagnification: Self.maxMagnification).width)
            }
            side = min(side, readable)
        } else if min(unit.width, unit.height) / side > 1.1 {
            side = min(1, max(unit.width, unit.height) / 0.9)
        }
        if side == current.width {
            // Já aparece (ao menos metade do que caberia na tela): não mexe.
            let shown = unit.intersection(current)
            let shownArea = shown.isNull ? 0 : shown.width * shown.height
            guard shownArea < min(unit.width * unit.height, side * side) * 0.5 else { return }
        }
        animateViewport(to: CGRect(x: unit.midX - side / 2, y: unit.midY - side / 2, width: side, height: side))
    }

    /// O item, ou o ancestral mais próximo com tamanho: um arquivo de 0 KB não
    /// tem área no mapa, então ele aparece pela pasta dele.
    func mapAnchor(for item: Int32) -> Int32? {
        lineage(item).reversed().first { size($0) > 0 || $0 == zoomItem }
    }

    /// Onde a seleção está no mapa (coordenadas unitárias): o retângulo do item,
    /// ou o da pasta (`anchor`) para um item de 0 KB. Calculado pelos tamanhos,
    /// não pelo bitmap na tela — contorno e pino não dependem de qual render já
    /// chegou. Guardado por seleção, pasta em zoom e geração do mapa (a view pede
    /// a cada quadro da animação).
    func selectionGeometry() -> (rect: CGRect, anchor: Int32)? {
        guard let item = selected else { return nil }
        let key = MarkerKey(item: item, root: zoomItem, generation: renderGeneration,
                            width: treemapSize.width, height: treemapSize.height)
        if let cached = markerCache, cached.key == key { return cached.value }
        let value = mapAnchor(for: item).flatMap { anchor in unitRect(of: anchor).map { ($0, anchor) } }
        markerCache = (key, value)
        return value
    }

    private struct MarkerKey: Equatable {
        let item: Int32, root: Int32, generation: Int, width: Int, height: Int
    }

    private var markerCache: (key: MarkerKey, value: (rect: CGRect, anchor: Int32)?)?

    /// Onde o item fica no mapa da pasta em zoom (coordenadas unitárias), mesmo
    /// fora da tela ou menor que um pixel; `nil` se não está dentro dela ou tem
    /// tamanho zero.
    func unitRect(of item: Int32) -> CGRect? {
        guard treemapSize.width > 0, treemapSize.height > 0, let source = renderSource() else { return nil }
        let path = lineage(item)
        guard let start = path.firstIndex(of: zoomItem) else { return nil }
        let width = CGFloat(treemapSize.width), height = CGFloat(treemapSize.height)
        guard let rect = TreemapRenderer.locate(Array(path[start...]), in: CGRect(x: 0, y: 0, width: width, height: height),
                                                source: source)
        else { return nil }
        return CGRect(x: rect.minX / width, y: rect.minY / height, width: rect.width / width, height: rect.height / height)
    }

    private func clamp(_ rect: CGRect) -> CGRect {
        var clamped = rect
        clamped.origin.x = min(max(0, rect.minX), 1 - rect.width)
        clamped.origin.y = min(max(0, rect.minY), 1 - rect.height)
        return clamped
    }

    /// Gesto do usuário: aplica na hora e interrompe a animação em curso.
    private func setViewport(_ rect: CGRect) {
        stopViewportAnimation()
        applyViewport(rect)
    }

    private func applyViewport(_ rect: CGRect) {
        let clamped = clamp(rect)
        guard clamped != viewport else { return }
        viewport = clamped
        viewportChanged()
    }

    // MARK: - Transição animada

    private var viewportAnimation: Timer?
    private var animationTarget = TreemapRenderer.fullViewport

    /// Transição suave como no Google Maps: o lado varia em escala logarítmica
    /// (cada dobra de zoom leva o mesmo tempo, mesmo de 1× a 2.000×) e o centro
    /// acompanha o progresso do zoom — num zoom em torno de um ponto, ele fica parado.
    private func animateViewport(to rect: CGRect) {
        let target = clamp(rect)
        let start = viewport
        stopViewportAnimation()
        guard target != start else { return }
        animationTarget = target
        // Destino longe (várias telas): afasta no meio do caminho para os dois
        // pontos caberem e aproxima no fim, em vez de atravessar telas borradas.
        let distance = hypot(target.midX - start.midX, target.midY - start.midY)
        let wider = max(start.width, target.width)
        let bump = distance > wider * 1.5 ? max(0, log(min(1, distance * 1.2) / wider)) : 0
        // Cada dobra de zoom leva o mesmo tempo: voos longos (2.000×) duram mais.
        let doublings = abs(log2(start.width / target.width)) + 2 * bump / log(2)
        let duration = min(1.2, 0.3 + 0.06 * doublings)
        let began = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.animationStep(from: start, to: target, bump: bump, began: began, duration: duration)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        viewportAnimation = timer
    }

    private func animationStep(from start: CGRect, to target: CGRect, bump: CGFloat, began: TimeInterval,
                               duration: TimeInterval) {
        let t = min(1, (ProcessInfo.processInfo.systemUptime - began) / duration)
        let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        let (from, to) = (start.width, target.width)
        let side = exp(log(from) + (log(to) - log(from)) * eased + bump * 4 * eased * (1 - eased))
        // Sem o afastamento, o centro acompanha o progresso do zoom (ponto fixo
        // continua fixo); com ele, os dois cabem na tela no meio e basta o eased.
        let progress = bump > 0 || from == to ? eased : (from - side) / (from - to)
        let x = start.midX + (target.midX - start.midX) * progress
        let y = start.midY + (target.midY - start.midY) * progress
        applyViewport(t >= 1 ? target : CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side))
        if t >= 1 { stopViewportAnimation() }
    }

    private func stopViewportAnimation() {
        viewportAnimation?.invalidate()
        viewportAnimation = nil
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
            if zoomItem == item || index.isAncestor(item, of: zoomItem) {
                zoomItem = index.parent[Int(item)]
                viewport = TreemapRenderer.fullViewport
            }
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
