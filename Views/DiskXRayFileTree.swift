// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import AppKit
import SwiftUI

/// Árvore de pastas num `NSOutlineView` — o controle nativo e virtualizado do
/// macOS. Só as linhas visíveis existem; expandir, rolar, setas e ordenação
/// pelo cabeçalho são do próprio AppKit, então a navegação é instantânea mesmo
/// com milhões de itens.
struct FileTreeOutline: NSViewRepresentable {
    @ObservedObject var model: DiskXRayViewModel
    @Binding var pendingTrash: Int32?

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        coordinator.pendingTrash = $pendingTrash

        let outline = TreeOutlineView()
        outline.headerView = NSTableHeaderView()
        outline.rowHeight = 22
        outline.intercellSpacing = NSSize(width: 0, height: 0)
        outline.indentationPerLevel = 14
        outline.style = .plain
        outline.usesAlternatingRowBackgroundColors = true
        outline.gridStyleMask = []
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
            if column == .share { tableColumn.sortDescriptorPrototype = nil }
            if column != .share {
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(
                    key: "\(column.rawValue)", ascending: column.ascendingByDefault
                )
            }
            tableColumn.isHidden = !model.visibleColumns.contains(column)
            outline.addTableColumn(tableColumn)
            if column == .name { outline.outlineTableColumn = tableColumn }
        }

        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.target = coordinator
        outline.doubleAction = #selector(Coordinator.doubleClicked(_:))
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
        private static let freeSpaceIcon = symbol("circle.dashed", NSColor(srgbRed: 0.55, green: 0.78, blue: 0.62, alpha: 1))
        private static let unaccountedIcon = symbol("gearshape.fill", NSColor(srgbRed: 0.86, green: 0.64, blue: 0.28, alpha: 1))

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
                // Novo scan: estado zerado, raiz expandida.
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
            case .share:
                let cell = reuse(outlineView, "share") { ShareCell() }
                cell.fraction = model.fractionOfParent(id)
                cell.label = model.text(.share, id)
                cell.needsDisplay = true
                return cell
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
        /// o ícone genérico na hora e o real carregado em segundo plano.
        private func icon(for id: Int32) -> NSImage? {
            switch id {
            case DiskXRayViewModel.freeSpaceItem: return Self.freeSpaceIcon
            case DiskXRayViewModel.unaccountedItem: return Self.unaccountedIcon
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

        private static func symbol(_ name: String, _ color: NSColor) -> NSImage {
            let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                .applying(.init(paletteColors: [color]))
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) ?? NSImage()
        }

        // MARK: Seleção, ordenação, ações

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !updatingFromModel, let outline = notification.object as? NSOutlineView,
                  let node = outline.item(atRow: outline.selectedRow) as? Node else { return }
            model.select(node.id, reveal: false)
        }

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
            guard !updatingFromModel, let descriptor = outlineView.sortDescriptors.first,
                  let key = descriptor.key, let raw = Int(key),
                  let column = DiskXRayViewModel.TreeColumn(rawValue: raw) else { return }
            model.setTreeSort(column, ascending: descriptor.ascending)
        }

        /// Duplo clique: arquivo abre no Quick Look; pasta alterna.
        @objc func doubleClicked(_ sender: NSOutlineView) {
            guard let node = sender.item(atRow: sender.clickedRow) as? Node else { return }
            toggleOrOpen(node)
        }

        private func toggleOrOpen(_ node: Node) {
            guard let outline else { return }
            if model.hasChildren(node.id) {
                if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
            } else {
                model.quickLook(node.id)
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
            add(String(localized: "Quick Look")) { [weak self] in self?.model.quickLook(id) }
            add(String(localized: "Open")) { [weak self] in self?.model.open(id) }
            add(String(localized: "Show in Finder")) { [weak self] in self?.model.revealInFinder(id) }
            add(String(localized: "Copy Path")) { [weak self] in self?.model.copyPath(id) }
            menu.addItem(.separator())
            add(String(localized: "Zoom Map Here")) { [weak self] in self?.model.zoom(into: id) }
            menu.addItem(.separator())
            add(String(localized: "Move to Trash…"), enabled: model.canTrash(id)) { [weak self] in self?.pendingTrash?.wrappedValue = id }
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

/// Coluna "Share": cápsula com a fração do pai e a porcentagem ao lado.
private final class ShareCell: NSView {
    var fraction = 0.0
    var label = ""

    override var isFlipped: Bool { true }

    override func draw(_: NSRect) {
        let track = NSRect(x: 4, y: bounds.midY - 3, width: max(0, bounds.width - 58), height: 6)
        guard track.width > 4 else { return }
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        let filled = NSRect(x: track.minX, y: track.minY, width: max(2, track.width * CGFloat(min(1, fraction))), height: track.height)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 3, yRadius: 3).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.maxX - size.width - 4, y: bounds.midY - size.height / 2))
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
