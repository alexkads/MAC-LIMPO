import AppKit
import Foundation
import UniformTypeIdentifiers

/// Estado da janela no modelo do WinDirStat (CWinDirStatModel + os controles
/// FileTree, FileTop, ExtensionList e TreeMap). As regras citam a fonte.
@MainActor
final class DiskXRayViewModel: ObservableObject {
    // MARK: - Varredura

    @Published private(set) var overview: DiskOverview?
    @Published private(set) var index: DiskScanIndex?
    @Published private(set) var scanRoot = DiskXRayService.dataRoot
    @Published private(set) var isScanning = false
    @Published private(set) var progress: DiskScanner.Progress?
    @Published private(set) var scanStarted: Date?
    @Published var errorMessage: String?
    private var scanCancel: CancelFlag?
    private let firmlinks = Firmlinks.system()

    /// O volume inteiro (o "drive"), não uma pasta: só ele tem <Free Space> e <Unknown>.
    var isDriveScan: Bool { scanRoot == DiskXRayService.dataRoot }

    // MARK: - Opções (Options.h, padrões)

    /// ShowFreeSpace (F6), padrão false.
    @Published var showFreeSpace = false { didSet { structureChanged() } }
    /// ShowUnknown (F7), padrão false.
    @Published var showUnknown = false { didSet { structureChanged() } }
    /// TreeMapUseLogical (Ctrl+L), padrão false.
    @Published var useLogicalSize = false { didSet { structureChanged() } }
    /// LargeFileCount, padrão 50.
    static let largeFileCount = 50

    // MARK: - Itens sintéticos

    static let unknownItem: Int32 = -2
    static let freeSpaceItem: Int32 = -3
    static let largestFilesRoot: Int32 = -4

    // MARK: - Árvore ("All Files")

    enum TreeColumn: Int, CaseIterable, Identifiable {
        case name, sizeProportion, percentage, physicalSize, logicalSize, items, files, folders, lastChange

        var id: Int { rawValue }

        /// IDS_COL_* (lang_en.txt)
        var title: String {
            switch self {
            case .name: "Name"
            case .sizeProportion: "Size Proportion"
            case .percentage: "Percentage"
            case .physicalSize: "Physical Size"
            case .logicalSize: "Logical Size"
            case .items: "Items"
            case .files: "Files"
            case .folders: "Folders"
            case .lastChange: "Last Change"
            }
        }

        /// FileTreeView.cpp:15-29
        var width: CGFloat {
            switch self {
            case .name: 250
            case .sizeProportion: 135
            case .lastChange: 120
            default: 90
            }
        }

        var alignLeft: Bool { self == .name || self == .lastChange }
        /// Name e Size Proportion não podem ser ocultadas.
        var isRequired: Bool { self == .name || self == .sizeProportion }
        /// GetAscendingDefault: só Name e Last Change sobem por padrão.
        var ascendingByDefault: Bool { self == .name || self == .lastChange }
    }

    /// Options.cpp:151 — {1,1,1,1,1,0,1,0,1,...}
    @Published var visibleColumns: Set<TreeColumn> = [
        .name, .sizeProportion, .percentage, .physicalSize, .logicalSize, .files, .lastChange
    ]

    @Published private(set) var sortColumn: TreeColumn = .sizeProportion
    @Published private(set) var sortAscending = false
    private var secondaryColumn: TreeColumn = .name
    private var secondaryAscending = true

    @Published private(set) var selected: Int32?
    /// Incrementado quando a seleção deve aparecer na árvore (expandir o caminho
    /// e rolar até ela) — ex.: clique no treemap.
    @Published private(set) var revealToken = 0
    /// Incrementado quando a estrutura ou a ordem da árvore muda (novo scan,
    /// ordenação, F6/F7/Ctrl+L, Lixeira): a árvore nativa recarrega.
    @Published private(set) var treeVersion = 0
    /// Nome do volume, lido uma vez por scan.
    private var volumeName = "Macintosh HD"
    private var sortedChildren: [Int32: [Int32]] = [:]

    enum Pane { case tree, largestFiles, extensions }

    @Published var focusedPane: Pane = .tree

    enum Tab: String, CaseIterable, Identifiable {
        case allFiles = "All Files"
        case largestFiles = "Largest Files"
        var id: String { rawValue }
    }

    @Published var tab: Tab = .allFiles

    // MARK: - Largest Files

    /// Os LargeFileCount maiores pelo tamanho lógico (FileTopControl.h:30-33),
    /// exibidos por Physical Size decrescente.
    @Published private(set) var largestFiles: [Int32] = []

    // MARK: - Extensões

    enum ExtensionColumn: Int, CaseIterable, Identifiable {
        case extensionName, color, description, bytes, percentBytes, files
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .extensionName: "Extension"
            case .color: "Color"
            case .description: "Description"
            case .bytes: "Bytes"
            case .percentBytes: "% Bytes"
            case .files: "Files"
            }
        }

        /// Larguras de ExtensionListControl.cpp:158-171 alargadas para caber o
        /// conteúdo, como AutomaticallyResizeColumns (padrão true) faz.
        var width: CGFloat {
            switch self {
            case .extensionName: 78
            case .color: 40
            case .description: 170
            case .bytes: 84
            case .percentBytes: 66
            case .files: 72
            }
        }

        var alignLeft: Bool { self == .extensionName || self == .color || self == .description }
        var ascendingByDefault: Bool { self == .extensionName || self == .percentBytes || self == .description }
    }

    @Published private(set) var extensionRows: [Int32] = []
    @Published private(set) var extensionSort: ExtensionColumn = .bytes
    @Published private(set) var extensionSortAscending = false
    @Published private(set) var selectedExtension: Int32?
    private var extensionColors: [CushionTreemap.RGB] = []
    private var descriptions: [String: String] = [:]
    private var swatches: [Int32: CGImage] = [:]
    private var fileIcons: [String: NSImage] = [:]
    private var folderIcons: [Int32: NSImage] = [:]

    // MARK: - Treemap

    @Published private(set) var zoomItem: Int32 = 0
    @Published private(set) var rendering: CushionTreemap.Rendering?
    @Published private(set) var isRendering = false
    private struct HighlightKey: Equatable {
        let image: ObjectIdentifier
        let ext: Int32
        let version: Int
    }

    private var highlightKey: HighlightKey?
    private var highlightCache: [CGRect] = []

    /// Pilha do "Reselect Child": os filhos de onde Select Parent saiu.
    private var reselectStack: [Int32] = []
    private var treemapSize: (width: Int, height: Int) = (0, 0)
    private var renderTask: Task<Void, Never>?
    private var renderCancel: CancelFlag?
    var treemapBackground = CushionTreemap.RGB(r: 255, g: 255, b: 255)
    var treemapShadow = CushionTreemap.RGB(r: 160, g: 160, b: 160)

    var isZoomed: Bool { index != nil && zoomItem != index?.root }

    // MARK: - Scan

    func startScan(root: String = DiskXRayService.dataRoot) {
        scanCancel?.set()
        renderCancel?.set()
        let cancel = CancelFlag()
        scanCancel = cancel

        scanRoot = root
        isScanning = true
        progress = nil
        scanStarted = Date()
        errorMessage = nil
        index = nil
        rendering = nil
        selected = nil
        selectedExtension = nil
        largestFiles = []
        extensionRows = []
        sortedChildren = [:]
        swatches = [:]
        folderIcons = [:]
        reselectStack = []

        Task { [weak self] in
            let overview = await runBlocking { DiskXRayService.shared.overview() }
            guard let self, !cancel.isSet else { return }
            self.overview = overview
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
            volumeName = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]))?
                .volumeLocalizedName ?? "Macintosh HD"
            index = scanned
            zoomItem = scanned.root
            assignExtensionColors()
            sortExtensions()
            refreshLargestFiles()
            treeVersion += 1
            select(scanned.root, reveal: false)
            scheduleRender()

            // Desenvolvimento: estado de demonstração para conferir o visual.
            if ProcessInfo.processInfo.environment["MACLIMPO_XRAY_DEMO"] == "1" {
                showUnknown = true
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
        treeVersion += 1
        scheduleRender()
    }

    // MARK: - Tamanhos

    private func isPseudoVisible(_ item: Int32) -> Bool {
        switch item {
        case Self.unknownItem: isDriveScan && showUnknown
        case Self.freeSpaceItem: isDriveScan && showFreeSpace
        default: true
        }
    }

    /// <Free Space>: espaço livre do volume.
    var freeSpaceBytes: Int64 { overview?.free ?? 0 }

    /// <Unknown>: max(0, (total − free) − tallied), sem contar o livre
    /// (Item.Extended.cpp:685-704).
    var unknownBytes: Int64 {
        guard let overview, let index else { return 0 }
        return max(0, overview.used - index.physical[0])
    }

    /// Tamanho na base atual (físico, ou lógico com Use Logical Size).
    func size(_ item: Int32) -> Int64 {
        switch item {
        case Self.unknownItem: return unknownBytes
        case Self.freeSpaceItem: return freeSpaceBytes
        case Self.largestFilesRoot: return 0
        default:
            guard let index else { return 0 }
            var value = useLogicalSize ? index.logical[Int(item)] : index.physical[Int(item)]
            if item == index.root, isDriveScan {
                if showUnknown { value += unknownBytes }
                if showFreeSpace { value += freeSpaceBytes }
            }
            return value
        }
    }

    func physicalSize(_ item: Int32) -> Int64? {
        guard let index else { return nil }
        switch item {
        case Self.unknownItem: return unknownBytes
        case Self.freeSpaceItem: return freeSpaceBytes
        case Self.largestFilesRoot: return nil
        default:
            var value = index.physical[Int(item)]
            if item == index.root, isDriveScan {
                if showUnknown { value += unknownBytes }
                if showFreeSpace { value += freeSpaceBytes }
            }
            return value
        }
    }

    func logicalSize(_ item: Int32) -> Int64? {
        guard let index else { return nil }
        switch item {
        case Self.unknownItem, Self.freeSpaceItem: return nil
        case Self.largestFilesRoot: return nil
        default: return index.logical[Int(item)]
        }
    }

    func parent(_ item: Int32) -> Int32? {
        guard let index else { return nil }
        if item < 0 { return item == Self.largestFilesRoot ? nil : index.root }
        return item == index.root ? nil : index.parent[Int(item)]
    }

    /// GetFraction: fração do pai.
    func fractionOfParent(_ item: Int32) -> Double {
        guard let parent = parent(item) else { return 1 }
        let total = size(parent)
        return total > 0 ? Double(size(item)) / Double(total) : 0
    }

    /// GetAbsoluteFraction: fração da raiz do scan.
    func fractionOfRoot(_ item: Int32) -> Double {
        guard let index else { return 0 }
        let total = size(index.root)
        return total > 0 ? Double(size(item)) / Double(total) : 0
    }

    // MARK: - Texto das colunas (Item.Extended.cpp:169-258)

    func name(_ item: Int32) -> String {
        switch item {
        case Self.unknownItem: return "<Unknown>"
        case Self.freeSpaceItem: return "<Free Space>"
        case Self.largestFilesRoot: return "Largest Files"
        default:
            guard let index else { return "" }
            guard item == index.root else { return index.name(item) }
            guard isDriveScan, let overview else { return firmlinks.displayPath(index.rootPath) }
            // "{vol} - {free} free of {total} ({pct}%)" (Item.Extended.cpp:637-640)
            let volume = volumeName
            let pct = overview.capacity == 0 ? 0 : 100.0 * Double(overview.free) / Double(overview.capacity)
            return "\(volume) - \(WinDirStatFormat.bytes(overview.free)) free of " +
                "\(WinDirStatFormat.bytes(overview.capacity)) (\(WinDirStatFormat.double(pct))%)"
        }
    }

    /// Caminho real (para abrir, revelar, copiar).
    func path(_ item: Int32) -> String {
        guard let index, item >= 0 else { return "" }
        return firmlinks.displayPath(index.path(item))
    }

    func text(_ column: TreeColumn, _ item: Int32) -> String {
        let isPseudo = item < 0
        switch column {
        case .name: return name(item)
        case .sizeProportion: return ""
        case .percentage:
            guard item != Self.largestFilesRoot else { return "" }
            // UseAbsolutePercentages (padrão true): fração da raiz.
            return WinDirStatFormat.percent(fractionOfRoot(item))
        case .physicalSize: return physicalSize(item).map(WinDirStatFormat.bytes) ?? ""
        case .logicalSize: return logicalSize(item).map(WinDirStatFormat.bytes) ?? ""
        case .items:
            guard let index, !isPseudo, index.isDirectory(item) else { return "" }
            return WinDirStatFormat.count(Int(index.fileCount[Int(item)] + index.folderCount[Int(item)]))
        case .files:
            guard let index, !isPseudo, index.isDirectory(item) else { return "" }
            return WinDirStatFormat.count(Int(index.fileCount[Int(item)]))
        case .folders:
            guard let index, !isPseudo, index.isDirectory(item) else { return "" }
            return WinDirStatFormat.count(Int(index.folderCount[Int(item)]))
        case .lastChange:
            guard let index, !isPseudo else { return "" }
            return WinDirStatFormat.fileTime(index.modified[Int(item)])
        }
    }

    func sizeProportionTooltip(_ item: Int32) -> String {
        "Size proportion of total scan: \(WinDirStatFormat.double(fractionOfRoot(item) * 100))%\n" +
            "Size proportion of parent folder: \(WinDirStatFormat.double(fractionOfParent(item) * 100))%"
    }

    func isDirectory(_ item: Int32) -> Bool {
        guard let index, item >= 0 else { return false }
        return index.isDirectory(item)
    }

    func isUnreadable(_ item: Int32) -> Bool {
        guard let index, item >= 0 else { return false }
        return index.isUnreadable(item)
    }

    func icon(_ item: Int32) -> NSImage? {
        guard let index, item >= 0 else { return nil }
        if index.isDirectory(item) {
            if let cached = folderIcons[item] { return cached }
            let image = NSWorkspace.shared.icon(forFile: path(item))
            folderIcons[item] = image
            return image
        }
        let ext = index.extensionName(item) ?? ""
        if let cached = fileIcons[ext] { return cached }
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: String(ext.dropFirst())) ?? .data)
        let image = NSWorkspace.shared.icon(for: type)
        fileIcons[ext] = image
        return image
    }

    // MARK: - Árvore: filhos, ordenação, linhas

    func hasChildren(_ item: Int32) -> Bool {
        if item == Self.largestFilesRoot { return !largestFiles.isEmpty }
        guard let index, item >= 0 else { return false }
        if item == index.root, isDriveScan, showUnknown || showFreeSpace { return true }
        return index.isDirectory(item) && index.hasChildren(item)
    }

    /// Filhos ordenados pela coluna atual (ordenação hierárquica entre irmãos).
    func treeChildren(_ item: Int32) -> [Int32] {
        if let cached = sortedChildren[item] { return cached }
        guard let index, item >= 0 else { return [] }
        var kids = index.children(item)
        if item == index.root, isDriveScan {
            if showFreeSpace { kids.append(Self.freeSpaceItem) }
            if showUnknown { kids.append(Self.unknownItem) }
        }
        kids.sort { compare($0, $1) }
        sortedChildren[item] = kids
        return kids
    }

    private func compare(_ a: Int32, _ b: Int32) -> Bool {
        let primary = compare(a, b, by: sortColumn)
        if primary != 0 { return sortAscending ? primary < 0 : primary > 0 }
        let secondary = compare(a, b, by: secondaryColumn)
        return secondaryAscending ? secondary < 0 : secondary > 0
    }

    /// Comparação crescente de uma coluna (CompareSibling).
    private func compare(_ a: Int32, _ b: Int32, by column: TreeColumn) -> Int {
        func cmp<T: Comparable>(_ x: T, _ y: T) -> Int { x < y ? -1 : (x > y ? 1 : 0) }
        switch column {
        case .name:
            // Tipo primeiro: dir(4) < file(8) < free(16) < unknown(32).
            let byType = cmp(typeRank(a), typeRank(b))
            if byType != 0 { return byType }
            return name(a).localizedCaseInsensitiveCompare(name(b)).rawValue
        case .sizeProportion, .percentage:
            return cmp(size(a), size(b))
        case .physicalSize:
            return cmp(physicalSize(a) ?? 0, physicalSize(b) ?? 0)
        case .logicalSize:
            return cmp(logicalSize(a) ?? 0, logicalSize(b) ?? 0)
        case .items, .files, .folders:
            return cmp(countValue(a, column), countValue(b, column))
        case .lastChange:
            return cmp(a >= 0 ? index?.modified[Int(a)] ?? 0 : 0, b >= 0 ? index?.modified[Int(b)] ?? 0 : 0)
        }
    }

    private func typeRank(_ item: Int32) -> Int {
        switch item {
        case Self.freeSpaceItem: 16
        case Self.unknownItem: 32
        default: isDirectory(item) ? 4 : 8
        }
    }

    private func countValue(_ item: Int32, _ column: TreeColumn) -> Int32 {
        guard let index, item >= 0 else { return 0 }
        switch column {
        case .files: return index.fileCount[Int(item)]
        case .folders: return index.folderCount[Int(item)]
        default: return index.fileCount[Int(item)] + index.folderCount[Int(item)]
        }
    }

    /// Clique no cabeçalho (WdsListControl.cpp:1096-1111).
    func sortTree(by column: TreeColumn) {
        if column == sortColumn {
            sortAscending.toggle()
        } else {
            secondaryColumn = sortColumn
            secondaryAscending = sortAscending
            sortColumn = column
            sortAscending = column.ascendingByDefault
        }
        sortedChildren = [:]
        treeVersion += 1
    }

    /// Ordenação vinda do cabeçalho nativo (coluna e direção já decididas).
    func setTreeSort(_ column: TreeColumn, ascending: Bool) {
        guard column != sortColumn || ascending != sortAscending else { return }
        if column != sortColumn {
            secondaryColumn = sortColumn
            secondaryAscending = sortAscending
        }
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
        // Seleção na árvore seleciona a extensão do arquivo (ExtensionView.cpp:105-126).
        if let index, item >= 0, !index.isDirectory(item) {
            selectedExtension = index.extensionIndex[Int(item)]
        }
        if reveal { revealToken += 1 }
    }

    /// Ancestrais a expandir para o item aparecer na árvore (raiz primeiro).
    func lineage(_ item: Int32) -> [Int32] {
        guard let index else { return [] }
        if item < 0 { return [index.root, item] }
        return index.lineage(item)
    }

    // MARK: - Largest Files

    private func refreshLargestFiles() {
        guard let index else { return }
        largestFiles = index.largestFiles(in: index.root, limit: Self.largeFileCount, logicalSize: true)
            .sorted { index.physical[Int($0)] > index.physical[Int($1)] }
    }

    // MARK: - Extensões

    /// Ranking por bytes decrescente; posição i recebe palette[min(i, 17)]
    /// (WinDirStatModel.cpp:425-486).
    private func assignExtensionColors() {
        guard let index else { return }
        let order = index.extensions.indices.sorted { index.extensionLogical[$0] > index.extensionLogical[$1] }
        var colors = [CushionTreemap.RGB](repeating: CushionTreemap.defaultPalette.last!, count: index.extensions.count)
        let last = CushionTreemap.defaultPalette.count - 1
        for (rank, ext) in order.enumerated() {
            colors[ext] = CushionTreemap.defaultPalette[min(rank, last)]
        }
        extensionColors = colors
    }

    func sortExtensions(by column: ExtensionColumn? = nil) {
        if let column {
            if column == extensionSort {
                extensionSortAscending.toggle()
            } else {
                extensionSort = column
                extensionSortAscending = column.ascendingByDefault
            }
        }
        guard let index else { return }
        let ascending = extensionSortAscending
        let sort = extensionSort
        extensionRows = index.extensions.indices
            .filter { index.extensionFiles[$0] > 0 }
            .map(Int32.init)
            .sorted { a, b in
                let order: ComparisonResult
                switch sort {
                case .extensionName, .color:
                    order = index.extensions[Int(a)].localizedCaseInsensitiveCompare(index.extensions[Int(b)])
                case .description:
                    order = extensionDescription(a).localizedCaseInsensitiveCompare(extensionDescription(b))
                case .bytes, .percentBytes:
                    let x = index.extensionLogical[Int(a)], y = index.extensionLogical[Int(b)]
                    order = x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
                case .files:
                    let x = index.extensionFiles[Int(a)], y = index.extensionFiles[Int(b)]
                    order = x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
                }
                if order == .orderedSame { return index.extensionLogical[Int(a)] > index.extensionLogical[Int(b)] }
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
    }

    func extensionName(_ ext: Int32) -> String { index?.extensions[Int(ext)] ?? "" }

    /// Nome do tipo (SHGetFileInfo szTypeName → UTType), "No Extension" para "".
    func extensionDescription(_ ext: Int32) -> String {
        let key = extensionName(ext)
        guard !key.isEmpty else { return "No Extension" }
        if let cached = descriptions[key] { return cached }
        let bare = String(key.dropFirst())
        let text = UTType(filenameExtension: bare)?.localizedDescription ?? "\(bare.uppercased()) File"
        descriptions[key] = text
        return text
    }

    func extensionBytes(_ ext: Int32) -> Int64 { index?.extensionLogical[Int(ext)] ?? 0 }
    func extensionFiles(_ ext: Int32) -> Int32 { index?.extensionFiles[Int(ext)] ?? 0 }

    /// % Bytes: bytes (lógicos) sobre o tamanho físico da raiz (WinDirStatModel.cpp:255-260).
    func extensionPercent(_ ext: Int32) -> String {
        guard let index, index.physical[0] > 0 else { return "" }
        return WinDirStatFormat.percent(Double(extensionBytes(ext)) / Double(index.physical[0]))
    }

    func extensionIcon(_ ext: Int32) -> NSImage {
        let key = extensionName(ext)
        if let cached = fileIcons[key] { return cached }
        let type = key.isEmpty ? UTType.data : (UTType(filenameExtension: String(key.dropFirst())) ?? .data)
        let image = NSWorkspace.shared.icon(for: type)
        fileIcons[key] = image
        return image
    }

    func swatch(_ ext: Int32, width: Int, height: Int) -> CGImage? {
        if let cached = swatches[ext] { return cached }
        let image = CushionTreemap.colorPreview(
            CushionTreemap.GraphColor(rgb: extensionColors[Int(ext)]), width: width, height: height
        )
        swatches[ext] = image
        return image
    }

    func selectExtension(_ ext: Int32) {
        selectedExtension = ext
        focusedPane = .extensions
    }

    // MARK: - Treemap

    /// Filhos para o layout: por tamanho decrescente, zeros no fim.
    private func treemapChildren(_ item: Int32) -> [Int32] {
        guard let index, item >= 0 else { return [] }
        var kids = index.children(item)
        if item == index.root, isDriveScan {
            if showFreeSpace { kids.append(Self.freeSpaceItem) }
            if showUnknown { kids.append(Self.unknownItem) }
        }
        if useLogicalSize || item == index.root {
            kids.sort { size($0) > size($1) }
        }
        return kids
    }

    /// TmiIsLeaf: arquivos e pseudo-itens; pastas são folhas só sem filhos.
    private func isLeaf(_ item: Int32) -> Bool {
        guard let index, item >= 0 else { return true }
        return !index.isDirectory(item) || !index.hasChildren(item)
    }

    func treemapResized(width: Int, height: Int) {
        guard width != treemapSize.width || height != treemapSize.height else { return }
        treemapSize = (width, height)
        scheduleRender(debounce: true)
    }

    func scheduleRender(debounce: Bool = false) {
        guard let index, treemapSize.width > 0, treemapSize.height > 0 else { return }
        renderCancel?.set()
        let cancel = CancelFlag()
        renderCancel = cancel
        let previous = renderTask
        let root = zoomItem
        let (width, height) = treemapSize
        let background = treemapBackground
        let shadow = treemapShadow
        // Snapshot do que o render consulta, para rodar fora do MainActor.
        let logical = useLogicalSize
        let colors = extensionColors
        let pseudo: [Int32: Int64] = [
            Self.freeSpaceItem: freeSpaceBytes, Self.unknownItem: unknownBytes
        ]
        let rootChildren = treemapChildren(index.root)
        isRendering = true

        renderTask = Task {
            await previous?.value
            if debounce { try? await Task.sleep(for: .milliseconds(120)) }
            guard !cancel.isSet else { return }
            let result = await runBlocking {
                func weight(_ item: Int32) -> UInt64 {
                    if item < 0 { return UInt64(max(0, pseudo[item] ?? 0)) }
                    return UInt64(max(0, logical ? index.logical[Int(item)] : index.physical[Int(item)]))
                }
                return CushionTreemap.render(
                    index: index, root: root, width: width, height: height,
                    background: background, shadow: shadow,
                    color: { item in
                        switch item {
                        case DiskXRayViewModel.unknownItem: return .unknown
                        case DiskXRayViewModel.freeSpaceItem: return .freeSpace
                        default:
                            guard !index.isDirectory(item) else { return .black }
                            return CushionTreemap.GraphColor(rgb: colors[Int(index.extensionIndex[Int(item)])])
                        }
                    },
                    isLeaf: { item in item < 0 || !index.isDirectory(item) || !index.hasChildren(item) },
                    weight: weight,
                    children: { item in
                        if item == index.root { return rootChildren }
                        var kids = index.children(item)
                        if logical { kids.sort { index.logical[Int($0)] > index.logical[Int($1)] } }
                        return kids
                    },
                    isCancelled: { cancel.isSet }
                )
            }
            guard !cancel.isSet else { return }
            rendering = result
            isRendering = false
        }
    }

    func item(atPixel point: CGPoint) -> Int32? {
        guard let rendering else { return nil }
        return CushionTreemap.hitTest(point, in: rendering, isLeaf: isLeaf, children: treemapChildren)
    }

    /// Clique: seleciona na árvore (expande o caminho).
    func clickTreemap(atPixel point: CGPoint) {
        guard let item = item(atPixel: point) else { return }
        focusedPane = .tree
        tab = .allFiles
        reselectStack = []
        select(item)
    }

    /// Duplo clique: seleciona e dá zoom (WinDirStatModel.Actions.cpp:417-428).
    func doubleClickTreemap(atPixel point: CGPoint) {
        guard let item = item(atPixel: point) else { return }
        select(item)
        zoomIn()
    }

    var canZoomIn: Bool { selected != nil && index != nil }

    /// Zoom In: arquivo → pasta pai; na raiz, reseta.
    func zoomIn() {
        guard let index, let selected else { return }
        var target = selected
        if target < 0 || !index.isDirectory(target) { target = parent(target) ?? index.root }
        if target == index.root {
            zoomReset()
            return
        }
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

    /// Roda para cima: Select Parent; para baixo: Reselect Child.
    func selectParent() {
        guard let selected, let parent = parent(selected) else { return }
        reselectStack.append(selected)
        select(parent)
    }

    func reselectChild() {
        guard let child = reselectStack.popLast() else { return }
        select(child)
    }

    /// Retângulos a destacar no treemap: seleção (foco na árvore/lista) ou
    /// todos os arquivos da extensão selecionada (foco nas extensões).
    func highlightRects() -> [CGRect] {
        guard let rendering, let index else { return [] }
        if focusedPane == .extensions {
            guard let ext = selectedExtension, !extensionName(ext).isEmpty else { return [] }
            // O hover redesenha o mapa a cada movimento do mouse; varrer a
            // subárvore inteira (milhões de itens) a cada vez travava a janela.
            let key = HighlightKey(image: ObjectIdentifier(rendering.image), ext: ext, version: treeVersion)
            if key == highlightKey { return highlightCache }
            let root = rendering.root
            guard root >= 0 else { return [] }
            var rects: [CGRect] = []
            for item in Int(root) ... Int(index.subtreeEnd[Int(root)])
                where index.extensionIndex[item] == ext && !index.isRemoved(Int32(item)) {
                if let rect = rendering.rects[Int32(item)], rect.width > 0, rect.height > 0 { rects.append(rect) }
            }
            highlightKey = key
            highlightCache = rects
            return rects
        }
        guard let selected, let rect = rendering.rects[selected], rect.width > 0, rect.height > 0 else { return [] }
        return [rect]
    }

    // MARK: - Barra de status (MainFrame.Commands.cpp:330-384)

    func statusText(hovered: Int32?) -> String {
        if let hovered { return hovered >= 0 ? path(hovered) : name(hovered) }
        if focusedPane == .extensions, let ext = selectedExtension { return "*" + extensionName(ext) }
        if let selected { return selected >= 0 ? path(selected) : name(selected) }
        return "Ready"
    }

    func statusSize(hovered: Int32?) -> String {
        guard let item = hovered ?? selected, item != Self.largestFilesRoot else { return "" }
        return (useLogicalSize ? "Logical Size: ∑ " : "Physical Size: ∑ ") + WinDirStatFormat.bytes(size(item))
    }

    // MARK: - Clean Up

    func open(_ item: Int32) {
        guard item >= 0 else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path(item)))
    }

    func selectInFinder(_ item: Int32) {
        guard item >= 0 else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path(item))])
    }

    func copyPath(_ item: Int32) {
        guard item >= 0 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path(item), forType: .string)
    }

    /// Delete (to Recycle Bin) → Lixeira. Nunca a raiz do scan nem a home e suas
    /// pastas-base; o resto depende da permissão do usuário no arquivo.
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
            // Nenhum render pode ler o índice enquanto ele muda.
            renderCancel?.set()
            await renderTask?.value
            index.remove(item)
            if let selected, selected >= 0, selected == item || index.isAncestor(item, of: selected) {
                self.selected = index.parent[Int(item)]
            }
            if zoomItem == item || index.isAncestor(item, of: zoomItem) { zoomItem = index.parent[Int(item)] }
            sortedChildren = [:]
            sortExtensions()
            refreshLargestFiles()
            treeVersion += 1
            scheduleRender()
        }
    }
}

/// Sinal de cancelamento para trabalho bloqueante fora do pool cooperativo.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
