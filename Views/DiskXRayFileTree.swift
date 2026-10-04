import AppKit
import SwiftUI

/// Árvore "All Files" num `NSOutlineView` — o controle nativo e virtualizado do
/// macOS, como o WinDirStat usa o list control nativo do Windows. Só as linhas
/// visíveis existem; expandir, rolar, setas e ordenação pelo cabeçalho são do
/// próprio AppKit.
struct FileTreeOutline: NSViewRepresentable {
    @ObservedObject var model: DiskXRayViewModel
    @Binding var pendingTrash: Int32?

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        coordinator.pendingTrash = $pendingTrash

        let outline = TreeOutlineView()
        outline.headerView = NSTableHeaderView()
        outline.rowHeight = 20
        outline.intercellSpacing = NSSize(width: 0, height: 0)
        outline.indentationPerLevel = 14
        outline.style = .plain
        outline.usesAlternatingRowBackgroundColors = false // ListStripes = false
        outline.gridStyleMask = [] // ListGrid = false
        outline.allowsMultipleSelection = false
        outline.allowsColumnReordering = true
        outline.allowsColumnResizing = true
        outline.columnAutoresizingStyle = .noColumnAutoresizing
        outline.autosaveExpandedItems = false

        for column in DiskXRayViewModel.TreeColumn.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(column.rawValue)"))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = 40
            tableColumn.headerCell.alignment = column.alignLeft ? .left : .right
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(
                key: "\(column.rawValue)", ascending: column.ascendingByDefault
            )
            tableColumn.isHidden = !model.visibleColumns.contains(column)
            outline.addTableColumn(tableColumn)
            if column == .name { outline.outlineTableColumn = tableColumn }
        }

        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.target = coordinator
        outline.doubleAction = #selector(Coordinator.doubleClicked(_:))
        outline.onFocus = { [weak coordinator] in coordinator?.model.focusedPane = .tree }
        outline.onKey = { [weak coordinator] key in coordinator?.handleKey(key) ?? false }

        let rowMenu = NSMenu()
        rowMenu.delegate = coordinator
        outline.menu = rowMenu
        let headerMenu = NSMenu()
        headerMenu.delegate = coordinator
        outline.headerView?.menu = headerMenu
        coordinator.rowMenu = rowMenu
        coordinator.headerMenu = headerMenu

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        coordinator.outline = outline
        coordinator.sync(force: true)
        return scroll
    }

    func updateNSView(_: NSScrollView, context: Context) {
        context.coordinator.pendingTrash = $pendingTrash
        context.coordinator.sync(force: false)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        let model: DiskXRayViewModel
        var pendingTrash: Binding<Int32?>?
        weak var outline: TreeOutlineView?
        weak var rowMenu: NSMenu?
        weak var headerMenu: NSMenu?

        /// Um objeto estável por item: o NSOutlineView identifica itens por objeto.
        final class Node: NSObject {
            let id: Int32
            init(_ id: Int32) { self.id = id }
        }

        private var nodes: [Int32: Node] = [:]
        private var lastIndex: ObjectIdentifier?
        private var lastTreeVersion = -1
        private var lastRevealToken = -1
        private var lastColumns: Set<DiskXRayViewModel.TreeColumn> = []
        private var updatingFromModel = false

        private var folderIcons: [Int32: NSImage] = [:]
        private var loadingIcons = Set<Int32>()
        private let iconQueue = DispatchQueue(label: "maclimpo.xray.icons", qos: .utility)
        private static let genericFolder = NSWorkspace.shared.icon(for: .folder)
        private static let freeSpaceIcon = glyph("▢", NSColor(srgbRed: 0x3A / 255, green: 0xCC / 255, blue: 0x3A / 255, alpha: 1))
        private static let unknownIcon = glyph("?", NSColor(srgbRed: 0xCC / 255, green: 0xB8 / 255, blue: 0x66 / 255, alpha: 1))

        init(model: DiskXRayViewModel) {
            self.model = model
        }

        private func node(_ id: Int32) -> Node {
            if let existing = nodes[id] { return existing }
            let created = Node(id)
            nodes[id] = created
            return created
        }

        // MARK: Sincronização com o modelo

        func sync(force: Bool) {
            guard let outline else { return }
            let indexID = model.index.map(ObjectIdentifier.init)

            if model.visibleColumns != lastColumns || force {
                lastColumns = model.visibleColumns
                for column in outline.tableColumns {
                    guard let raw = Int(column.identifier.rawValue),
                          let kind = DiskXRayViewModel.TreeColumn(rawValue: raw) else { continue }
                    column.isHidden = !model.visibleColumns.contains(kind)
                }
            }

            if indexID != lastIndex {
                // Novo scan: estado zerado, raiz inserida e expandida (TreeListControl.cpp:267-278).
                lastIndex = indexID
                nodes = [:]
                folderIcons = [:]
                lastTreeVersion = model.treeVersion
                updatingFromModel = true
                outline.reloadData()
                if let root = model.index?.root { outline.expandItem(node(root)) }
                syncSortIndicator()
                updatingFromModel = false
            } else if model.treeVersion != lastTreeVersion {
                lastTreeVersion = model.treeVersion
                reloadKeepingState()
            }

            if model.revealToken != lastRevealToken {
                lastRevealToken = model.revealToken
                if let selected = model.selected { reveal(selected) }
            }
        }

        /// Recarrega preservando o que estava expandido e a seleção.
        private func reloadKeepingState() {
            guard let outline else { return }
            var expandedIDs: [Int32] = []
            for row in 0 ..< outline.numberOfRows {
                if let item = outline.item(atRow: row) as? Node, outline.isItemExpanded(item) {
                    expandedIDs.append(item.id)
                }
            }
            updatingFromModel = true
            outline.reloadData()
            for id in expandedIDs where id < 0 || !(model.index?.isRemoved(id) ?? true) {
                outline.expandItem(node(id))
            }
            if let selected = model.selected {
                let row = outline.row(forItem: node(selected))
                if row >= 0 { outline.selectRowIndexes([row], byExtendingSelection: false) }
            }
            syncSortIndicator()
            updatingFromModel = false
        }

        /// Expande o caminho até o item, seleciona e rola até ele.
        private func reveal(_ id: Int32) {
            guard let outline else { return }
            updatingFromModel = true
            for ancestor in model.lineage(id).dropLast() {
                outline.expandItem(node(ancestor))
            }
            let row = outline.row(forItem: node(id))
            if row >= 0 {
                outline.selectRowIndexes([row], byExtendingSelection: false)
                outline.scrollRowToVisible(row)
            }
            updatingFromModel = false
        }

        private func syncSortIndicator() {
            guard let outline else { return }
            let descriptor = NSSortDescriptor(key: "\(model.sortColumn.rawValue)", ascending: model.sortAscending)
            if outline.sortDescriptors.first != descriptor { outline.sortDescriptors = [descriptor] }
        }

        // MARK: Data source

        func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? Node else { return model.index == nil ? 0 : 1 }
            return model.hasChildren(node.id) ? model.treeChildren(node.id).count : 0
        }

        func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let parent = item as? Node else { return node(model.index?.root ?? 0) }
            return node(model.treeChildren(parent.id)[index])
        }

        func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? Node else { return false }
            return model.hasChildren(node.id)
        }

        // MARK: Células

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let tableColumn, let node = item as? Node,
                  let raw = Int(tableColumn.identifier.rawValue),
                  let column = DiskXRayViewModel.TreeColumn(rawValue: raw)
            else { return nil }
            let id = node.id

            switch column {
            case .name:
                let cell = reuse(outlineView, "name") { NameCell() }
                cell.textField?.stringValue = model.name(id)
                cell.imageView?.image = icon(for: id)
                return cell
            case .sizeProportion:
                let bar = reuse(outlineView, "bar") { SizeProportionCell() }
                bar.subtree = model.fractionOfParent(id)
                bar.absolute = model.fractionOfRoot(id)
                bar.indent = outlineView.level(forItem: item)
                bar.toolTip = model.sizeProportionTooltip(id)
                bar.needsDisplay = true
                return bar
            default:
                let cell = reuse(outlineView, column.alignLeft ? "textLeft" : "textRight") {
                    TextCell(alignment: column.alignLeft ? .left : .right)
                }
                cell.textField?.stringValue = model.text(column, id)
                return cell
            }
        }

        private func reuse<T: NSView>(_ outline: NSOutlineView, _ identifier: String, make: () -> T) -> T {
            let id = NSUserInterfaceItemIdentifier(identifier)
            if let view = outline.makeView(withIdentifier: id, owner: nil) as? T { return view }
            let view = make()
            view.identifier = id
            return view
        }

        /// Ícones: arquivos pelo tipo (cache por extensão no modelo); pastas com
        /// o ícone genérico na hora e o real carregado em segundo plano, como o
        /// ícone de shell assíncrono do WinDirStat (Item.Extended.cpp:381-435).
        private func icon(for id: Int32) -> NSImage? {
            switch id {
            case DiskXRayViewModel.freeSpaceItem: return Self.freeSpaceIcon
            case DiskXRayViewModel.unknownItem: return Self.unknownIcon
            default: break
            }
            guard model.isDirectory(id) else { return model.icon(id) }
            if let cached = folderIcons[id] { return cached }
            if !loadingIcons.contains(id) {
                loadingIcons.insert(id)
                let path = model.path(id)
                iconQueue.async { [weak self] in
                    let image = NSWorkspace.shared.icon(forFile: path)
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.folderIcons[id] = image
                        self.loadingIcons.remove(id)
                        guard let outline = self.outline, let node = self.nodes[id] else { return }
                        let row = outline.row(forItem: node)
                        if row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? NameCell {
                            cell.imageView?.image = image
                        }
                    }
                }
            }
            return Self.genericFolder
        }

        private static func glyph(_ text: String, _ color: NSColor) -> NSImage {
            NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: color
                ]
                let string = NSAttributedString(string: text, attributes: attributes)
                let size = string.size()
                string.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
                return true
            }
        }

        // MARK: Seleção, ordenação, ações

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !updatingFromModel, let outline = notification.object as? NSOutlineView,
                  let node = outline.item(atRow: outline.selectedRow) as? Node else { return }
            model.focusedPane = .tree
            model.select(node.id, reveal: false)
        }

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
            guard !updatingFromModel, let descriptor = outlineView.sortDescriptors.first,
                  let key = descriptor.key, let raw = Int(key),
                  let column = DiskXRayViewModel.TreeColumn(rawValue: raw) else { return }
            model.setTreeSort(column, ascending: descriptor.ascending)
        }

        /// Duplo clique: arquivo abre pelo sistema; pasta alterna (TreeListControl.cpp:324-342).
        @objc func doubleClicked(_ sender: NSOutlineView) {
            guard let node = sender.item(atRow: sender.clickedRow) as? Node else { return }
            toggleOrOpen(node)
        }

        private func toggleOrOpen(_ node: Node) {
            guard let outline else { return }
            if model.hasChildren(node.id) {
                if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
            } else {
                model.open(node.id)
            }
        }

        /// Espaço alterna, Enter abre; setas ficam com o NSOutlineView.
        func handleKey(_ key: TreeOutlineView.Key) -> Bool {
            guard let outline, let node = outline.item(atRow: outline.selectedRow) as? Node else { return false }
            switch key {
            case .space:
                if model.hasChildren(node.id) { toggleOrOpen(node) }
            case .enter:
                model.open(node.id)
            }
            return true
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            menu.autoenablesItems = false
            if menu === headerMenu {
                for column in DiskXRayViewModel.TreeColumn.allCases {
                    let item = ActionMenuItem(title: column.title) { [weak self] in self?.model.toggleColumn(column) }
                    item.state = model.visibleColumns.contains(column) ? .on : .off
                    item.isEnabled = !column.isRequired
                    menu.addItem(item)
                }
                return
            }
            guard let outline, let node = outline.item(atRow: outline.clickedRow) as? Node, node.id >= 0 else { return }
            let id = node.id
            model.select(id, reveal: false)
            func add(_ title: String, enabled: Bool = true, _ action: @escaping () -> Void) {
                let item = ActionMenuItem(title: title, action: action)
                item.isEnabled = enabled
                menu.addItem(item)
            }
            add("Open…") { [weak self] in self?.model.open(id) }
            add("Select in Finder…") { [weak self] in self?.model.selectInFinder(id) }
            add("Copy Path") { [weak self] in self?.model.copyPath(id) }
            menu.addItem(.separator())
            add("Zoom In") { [weak self] in
                self?.model.select(id, reveal: false)
                self?.model.zoomIn()
            }
            add("Zoom Out", enabled: model.isZoomed) { [weak self] in self?.model.zoomOut() }
            add("Zoom Reset", enabled: model.isZoomed) { [weak self] in self?.model.zoomReset() }
            menu.addItem(.separator())
            add("Delete (to Trash)", enabled: model.canTrash(id)) { [weak self] in self?.pendingTrash?.wrappedValue = id }
        }
    }
}

// MARK: - Controle e células

/// NSOutlineView que avisa foco e trata Espaço/Enter.
final class TreeOutlineView: NSOutlineView {
    enum Key { case space, enter }

    var onFocus: (() -> Void)?
    var onKey: ((Key) -> Bool)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: if onKey?(.space) == true { return }
        case 36, 76: if onKey?(.enter) == true { return }
        default: break
        }
        super.keyDown(with: event)
    }
}

private final class NameCell: NSTableCellView {
    init() {
        super.init(frame: .zero)
        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.imageScaling = .scaleProportionallyUpOrDown
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = .byTruncatingTail
        text.font = .systemFont(ofSize: 12)
        addSubview(image)
        addSubview(text)
        imageView = image
        textField = text
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class TextCell: NSTableCellView {
    init(alignment: NSTextAlignment) {
        super.init(frame: .zero)
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.alignment = alignment
        text.lineBreakMode = .byTruncatingTail
        text.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        addSubview(text)
        textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Barra "Size Proportion" (Item.Extended.cpp:49-167): trilho, barra do subtree
/// (fração do pai) e barra absoluta (fração da raiz), cor por nível.
private final class SizeProportionCell: NSView {
    var subtree = 0.0
    var absolute = 0.0
    var indent = 0

    override var isFlipped: Bool { true }

    /// Options.h:260-267, FileTreeColors.
    private static let fileTreeColors: [(Double, Double, Double)] = [
        (64, 64, 140), (140, 64, 64), (64, 140, 64), (140, 140, 64),
        (0, 0, 255), (255, 0, 0), (0, 255, 0), (255, 255, 0)
    ]

    override func draw(_: NSRect) {
        typealias RGB = (Double, Double, Double)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // rc.Deflate(2, 4); rc.left += indent * SizeProportionIndent(16)
        var rc = bounds.insetBy(dx: 2, dy: 4)
        let indentWidth = CGFloat(indent) * 16
        rc.origin.x += indentWidth
        rc.size.width -= indentWidth
        guard rc.width > 0, rc.height > 0 else { return }

        let color = Self.fileTreeColors[indent % Self.fileTreeColors.count]
        let neutralBack: RGB = dark ? (40, 40, 40) : (225, 225, 225)
        let white: RGB = (255, 255, 255), black: RGB = (0, 0, 0)
        func blend(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
            let t = min(max(t, 0), 1)
            return ((a.0 + (b.0 - a.0) * t).rounded(), (a.1 + (b.1 - a.1) * t).rounded(), (a.2 + (b.2 - a.2) * t).rounded())
        }
        func blendDark(_ c: RGB, _ d: Double, _ l: Double) -> RGB { dark ? blend(c, white, d) : blend(c, black, l) }
        func ns(_ c: RGB) -> NSColor { NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1) }
        func roundRect(_ r: NSRect, fill: RGB, border: RGB) {
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.5, yRadius: 1.5)
            ns(fill).setFill()
            path.fill()
            ns(border).setStroke()
            path.stroke()
        }
        func fill(_ r: NSRect, _ c: RGB) {
            ns(c).setFill()
            r.fill()
        }

        let trackFill = blendDark(neutralBack, 0.10, 0.06)
        let trackBorder = blendDark(trackFill, 0.18, 0.18)
        let subtreeFill = dark ? blend(trackFill, color, 0.68) : blend(trackFill, color, 0.48)
        let subtreeGlow = blend(subtreeFill, white, dark ? 0.18 : 0.30)
        let absoluteFill = blendDark(color, 0.12, 0.10)
        let absoluteGlow = blend(absoluteFill, white, dark ? 0.16 : 0.26)
        let absoluteEdge = blend(absoluteFill, black, dark ? 0.18 : 0.12)

        roundRect(rc, fill: trackFill, border: trackBorder)
        rc = rc.insetBy(dx: 1, dy: 1)
        guard rc.width > 0, rc.height > 0 else { return }
        func fractionX(_ f: Double) -> CGFloat { rc.minX + (rc.width * CGFloat(min(max(f, 0), 1))).rounded() }

        let subtreeRight = fractionX(subtree)
        if subtreeRight > rc.minX {
            let r = NSRect(x: rc.minX, y: rc.minY, width: subtreeRight - rc.minX, height: rc.height)
            roundRect(r, fill: subtreeFill, border: subtreeFill)
            if r.height >= 3, r.width >= 2 { fill(NSRect(x: r.minX + 1, y: r.minY, width: r.width - 2, height: 1), subtreeGlow) }
            if subtreeRight < rc.maxX { fill(NSRect(x: subtreeRight, y: rc.minY, width: 1, height: rc.height), trackBorder) }
        }

        var absoluteRect = NSRect(x: rc.minX, y: rc.minY, width: fractionX(min(subtree, absolute)) - rc.minX, height: rc.height)
        absoluteRect = absoluteRect.insetBy(dx: 0, dy: 2)
        if absoluteRect.width > 0, absoluteRect.height > 0 {
            roundRect(absoluteRect, fill: absoluteFill, border: absoluteFill)
            if absoluteRect.height >= 3, absoluteRect.width >= 2 {
                fill(NSRect(x: absoluteRect.minX + 1, y: absoluteRect.minY, width: absoluteRect.width - 2, height: 1), absoluteGlow)
            }
            if absoluteRect.height >= 2 {
                fill(NSRect(x: absoluteRect.maxX - 1, y: absoluteRect.minY + 1, width: 1, height: absoluteRect.height - 2), absoluteEdge)
            }
        }
    }
}

/// NSMenuItem com closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() { handler() }
}
