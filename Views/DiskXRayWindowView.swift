import AppKit
import SwiftUI

/// Janela principal do WinDirStat: árvore ("All Files" / "Largest Files") e
/// lista de extensões em cima, treemap embaixo, barra de status.
struct DiskXRayWindowView: View {
    @StateObject private var model = DiskXRayViewModel()
    @StateObject private var hover = HoverState()
    @State private var pendingTrash: Int32?
    @Environment(\.colorScheme) private var colorScheme
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WdsToolbar(model: model, pendingTrash: $pendingTrash)
            Divider()
            VSplitView {
                HSplitView {
                    FileTabbedView(model: model, pendingTrash: $pendingTrash)
                        .frame(minWidth: 520, maxWidth: .infinity)
                    ExtensionListView(model: model)
                        .frame(minWidth: 300, idealWidth: 440, maxWidth: .infinity)
                }
                .frame(minHeight: 160, idealHeight: 330)
                TreeMapView(model: model, hover: hover, pendingTrash: $pendingTrash)
                    .frame(minHeight: 160, idealHeight: 380)
            }
            Divider()
            StatusBar(model: model, hover: hover)
        }
        .frame(minWidth: 960, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            applySystemColors()
            if model.index == nil, !model.isScanning { model.startScan() }
        }
        .onChange(of: colorScheme) {
            applySystemColors()
            model.scheduleRender()
        }
        .confirmationDialog(
            "Delete (to Trash)",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { item in
            Button("Move to Trash", role: .destructive) { model.moveToTrash(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("Do you really want to move \"\(model.path(item))\" (\(WinDirStatFormat.bytes(model.physicalSize(item) ?? 0))) to the Trash?")
        }
        .alert(
            "MAC-LIMPO",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// COLOR_WINDOW e COLOR_3DSHADOW do tema atual.
    private func applySystemColors() {
        model.treemapBackground = rgb(NSColor.windowBackgroundColor)
        model.treemapShadow = rgb(NSColor.separatorColor.blended(withFraction: 0.5, of: .gray) ?? .gray)
    }

    private func rgb(_ color: NSColor) -> CushionTreemap.RGB {
        let c = color.usingColorSpace(.deviceRGB) ?? .gray
        return CushionTreemap.RGB(
            r: Int(c.redComponent * 255), g: Int(c.greenComponent * 255), b: Int(c.blueComponent * 255)
        )
    }
}

@MainActor
final class HoverState: ObservableObject {
    @Published var item: Int32?
}

// MARK: - Cores compartilhadas

private enum Palette {
    /// Highlight de seleção sem foco: (190,190,190) claro / (90,90,90) escuro.
    static func selection(focused: Bool, dark: Bool) -> Color {
        if focused { return Color(nsColor: .selectedContentBackgroundColor) }
        return dark ? Color(red: 90 / 255, green: 90 / 255, blue: 90 / 255)
            : Color(red: 190 / 255, green: 190 / 255, blue: 190 / 255)
    }

    static let rowHeight: CGFloat = 20
}

// MARK: - Barra de ferramentas

private struct WdsToolbar: View {
    @ObservedObject var model: DiskXRayViewModel
    @Binding var pendingTrash: Int32?

    var body: some View {
        let selected = model.selected.flatMap { $0 >= 0 ? $0 : nil }
        HStack(spacing: 6) {
            Menu {
                Button("Macintosh HD") { model.startScan() }
                Button("Folder…") { model.chooseFolderAndScan() }
            } label: {
                Label("Select Target", systemImage: "internaldrive")
            }
            .fixedSize()
            .help("Select Target…")

            if model.isScanning {
                Button("Stop") { model.cancelScan() }
            } else {
                Button { model.startScan(root: model.scanRoot) } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh All")
                    .keyboardShortcut("r", modifiers: .command)
            }

            Divider().frame(height: 16)

            Button { model.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom In (+)")
                .keyboardShortcut("+", modifiers: [])
                .disabled(!model.canZoomIn)
            Button { model.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom Out (-)")
                .keyboardShortcut("-", modifiers: [])
                .disabled(!model.isZoomed)
            Button { model.zoomReset() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .help("Zoom Reset (Ctrl+.)")
                .keyboardShortcut(".", modifiers: .control)
                .disabled(!model.isZoomed)

            Divider().frame(height: 16)

            Toggle(isOn: $model.showFreeSpace) { Text("Free Space") }
                .toggleStyle(.button)
                .help("Show Free Space (F6)")
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF6FunctionKey)!)), modifiers: [])
                .disabled(!model.isDriveScan)
            Toggle(isOn: $model.showUnknown) { Text("Unknown") }
                .toggleStyle(.button)
                .help("Show Unknown (F7)")
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF7FunctionKey)!)), modifiers: [])
                .disabled(!model.isDriveScan)
            Toggle(isOn: $model.useLogicalSize) { Text("Logical Size") }
                .toggleStyle(.button)
                .help("Use Logical Size (Ctrl+L)")
                .keyboardShortcut("l", modifiers: .control)

            Divider().frame(height: 16)

            Button { selected.map(model.open) } label: { Image(systemName: "arrow.up.forward.app") }
                .help("Open…")
                .disabled(selected == nil)
            Button { selected.map(model.selectInFinder) } label: { Image(systemName: "folder") }
                .help("Select in Finder…")
                .disabled(selected == nil)
            Button { selected.map(model.copyPath) } label: { Image(systemName: "doc.on.doc") }
                .help("Copy Path")
                .disabled(selected == nil)
            Button { pendingTrash = selected } label: { Image(systemName: "trash") }
                .help("Delete (to Trash)")
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!(selected.map(model.canTrash) ?? false))

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

// MARK: - FileTabbedView

private struct FileTabbedView: View {
    @ObservedObject var model: DiskXRayViewModel
    @Binding var pendingTrash: Int32?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(DiskXRayViewModel.Tab.allCases) { tab in
                    Button(tab.rawValue) { model.tab = tab }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: model.tab == tab ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(model.tab == tab ? Color(nsColor: .controlBackgroundColor) : .clear)
                        .overlay(alignment: .bottom) {
                            if model.tab == tab { Rectangle().fill(Color.accentColor).frame(height: 2) }
                        }
                }
                Spacer()
            }
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.4))
            Divider()

            if model.index == nil {
                ScanProgressView(model: model)
            } else if model.tab == .allFiles {
                FileTreeOutline(model: model, pendingTrash: $pendingTrash)
            } else {
                LargestFilesView(model: model, pendingTrash: $pendingTrash)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ScanProgressView: View {
    @ObservedObject var model: DiskXRayViewModel

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            if model.isScanning {
                if let progress = model.progress, progress.estimatedItems > 0 {
                    ProgressView(value: min(1, Double(progress.items) / Double(progress.estimatedItems)))
                        .frame(maxWidth: 380)
                    Text("\(WinDirStatFormat.count(progress.items)) items · \(WinDirStatFormat.bytes(progress.physicalBytes))")
                        .font(.system(size: 12).monospacedDigit())
                    Text(Firmlinks.system().displayPath(progress.currentPath))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 520)
                } else {
                    ProgressView()
                }
                if let started = model.scanStarted {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        let seconds = Int(context.date.timeIntervalSince(started))
                        Text(String(format: "[%d:%02d]", seconds / 60, seconds % 60))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button("Select Target…") { model.startScan() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - All Files: ver DiskXRayFileTree.swift (NSOutlineView)

private struct HeaderCell: View {
    let title: String
    let sorted: Bool?
    let alignLeft: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if !alignLeft { Spacer(minLength: 0) }
                Text(title).lineLimit(1)
                if let ascending = sorted {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                }
                if alignLeft { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 5)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1) }
    }
}

/// Ícone do item; pseudo-itens com os glifos de IconHandler.cpp:32-38.
private struct ItemIcon: View {
    @ObservedObject var model: DiskXRayViewModel
    let item: Int32

    var body: some View {
        Group {
            switch item {
            case DiskXRayViewModel.freeSpaceItem:
                Text("▢").foregroundStyle(Color(red: 0x3A / 255, green: 0xCC / 255, blue: 0x3A / 255))
            case DiskXRayViewModel.unknownItem:
                Text("?").bold().foregroundStyle(Color(red: 0xCC / 255, green: 0xB8 / 255, blue: 0x66 / 255))
            case DiskXRayViewModel.largestFilesRoot:
                Text("⋙").foregroundStyle(.secondary)
            default:
                if let image = model.icon(item) {
                    Image(nsImage: image).resizable()
                }
            }
        }
        .font(.system(size: 13))
        .frame(width: 16, height: 16)
    }
}

private struct ItemMenu: View {
    @ObservedObject var model: DiskXRayViewModel
    let item: Int32
    @Binding var pendingTrash: Int32?

    var body: some View {
        if item >= 0 {
            Button("Open…") { model.open(item) }
            Button("Select in Finder…") { model.selectInFinder(item) }
            Button("Copy Path") { model.copyPath(item) }
            Divider()
            Button("Zoom In") {
                model.select(item, reveal: false)
                model.zoomIn()
            }
            Button("Zoom Out") { model.zoomOut() }.disabled(!model.isZoomed)
            Button("Zoom Reset") { model.zoomReset() }.disabled(!model.isZoomed)
            Divider()
            Button("Delete (to Trash)") { pendingTrash = item }.disabled(!model.canTrash(item))
        }
    }
}

// MARK: - Largest Files

private struct LargestFilesView: View {
    @ObservedObject var model: DiskXRayViewModel
    @Binding var pendingTrash: Int32?
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                content.frame(width: max(geometry.size.width, 500 + 90 + 90 + 120))
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HeaderCell(title: "Name", sorted: nil, alignLeft: true) {}.frame(minWidth: 500, maxWidth: .infinity)
                HeaderCell(title: "Physical Size", sorted: false, alignLeft: false) {}.frame(width: 90)
                HeaderCell(title: "Logical Size", sorted: nil, alignLeft: false) {}.frame(width: 90)
                HeaderCell(title: "Last Change", sorted: nil, alignLeft: true) {}.frame(width: 120)
            }
            Divider()
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    row(DiskXRayViewModel.largestFilesRoot, depth: 0)
                    ForEach(model.largestFiles, id: \.self) { item in
                        row(item, depth: 1)
                            .contextMenu { ItemMenu(model: model, item: item, pendingTrash: $pendingTrash) }
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onChange(of: focused) { if focused { model.focusedPane = .largestFiles } }
        }
    }

    private func row(_ item: Int32, depth: Int) -> some View {
        let isSelected = model.selected == item && item >= 0
        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                Spacer().frame(width: CGFloat(depth) * 16 + 4)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    .frame(width: 12).opacity(depth == 0 ? 1 : 0)
                ItemIcon(model: model, item: item)
                // Filhos mostram o caminho completo como nome (ItemTop.cpp:40-53).
                Text(item >= 0 ? model.path(item) : model.name(item)).lineLimit(1).truncationMode(.middle)
            }
            .frame(minWidth: 500, maxWidth: .infinity, alignment: .leading)
            Text(item >= 0 ? model.text(.physicalSize, item) : "").padding(.horizontal, 5).frame(width: 90, alignment: .trailing)
            Text(item >= 0 ? model.text(.logicalSize, item) : "").padding(.horizontal, 5).frame(width: 90, alignment: .trailing)
            Text(item >= 0 ? model.text(.lastChange, item) : "").padding(.horizontal, 5).frame(width: 120, alignment: .leading)
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(isSelected && focused ? Color.white : Color.primary)
        .frame(height: Palette.rowHeight)
        .background(isSelected ? Palette.selection(focused: focused, dark: colorScheme == .dark) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if item >= 0 { model.open(item) } }
        .simultaneousGesture(TapGesture().onEnded {
            guard item >= 0 else { return }
            model.focusedPane = .largestFiles
            model.select(item, reveal: false)
        })
    }
}

// MARK: - Extensões

private struct ExtensionListView: View {
    @ObservedObject var model: DiskXRayViewModel
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(DiskXRayViewModel.ExtensionColumn.allCases) { column in
                    HeaderCell(
                        title: column.title,
                        sorted: model.extensionSort == column ? model.extensionSortAscending : nil,
                        alignLeft: column.alignLeft
                    ) { model.sortExtensions(by: column) }
                        .frame(width: column == .description ? nil : column.width)
                        .frame(minWidth: column == .description ? column.width : nil,
                               maxWidth: column == .description ? .infinity : nil)
                }
            }
            .padding(.top, 25)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.extensionRows, id: \.self) { ext in
                            row(ext).id(ext)
                        }
                    }
                }
                .onChange(of: model.selectedExtension) {
                    if let ext = model.selectedExtension, model.focusedPane != .extensions { proxy.scrollTo(ext) }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onChange(of: focused) { if focused { model.focusedPane = .extensions } }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func row(_ ext: Int32) -> some View {
        let isSelected = model.selectedExtension == ext
        let name = model.extensionName(ext)
        return HStack(spacing: 0) {
            HStack(spacing: 3) {
                Image(nsImage: model.extensionIcon(ext)).resizable().frame(width: 16, height: 16)
                Text(name).lineLimit(1)
            }
            .padding(.leading, 4)
            .frame(width: DiskXRayViewModel.ExtensionColumn.extensionName.width, alignment: .leading)
            // DrawColor: rc.Deflate(2, 3), cushion recortada com cantos de 3.
            Group {
                if let image = model.swatch(ext, width: Int(36 * displayScale), height: Int((Palette.rowHeight - 6) * displayScale)) {
                    Image(decorative: image, scale: displayScale)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                }
            }
            .frame(width: 40, height: Palette.rowHeight)
            Text(model.extensionDescription(ext))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
            Text(WinDirStatFormat.bytes(model.extensionBytes(ext))).lineLimit(1).padding(.horizontal, 5)
                .frame(width: DiskXRayViewModel.ExtensionColumn.bytes.width, alignment: .trailing)
            Text(model.extensionPercent(ext)).lineLimit(1).padding(.horizontal, 5)
                .frame(width: DiskXRayViewModel.ExtensionColumn.percentBytes.width, alignment: .trailing)
            Text(WinDirStatFormat.count(Int(model.extensionFiles(ext)))).lineLimit(1).padding(.horizontal, 5)
                .frame(width: DiskXRayViewModel.ExtensionColumn.files.width, alignment: .trailing)
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(isSelected && focused ? Color.white : Color.primary)
        .frame(height: Palette.rowHeight)
        .background(isSelected ? Palette.selection(focused: focused, dark: colorScheme == .dark) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            focused = true
            model.selectExtension(ext)
        }
    }
}

// MARK: - Treemap

private struct TreeMapView: View {
    @ObservedObject var model: DiskXRayViewModel
    @ObservedObject var hover: HoverState
    @Binding var pendingTrash: Int32?
    @Environment(\.displayScale) private var displayScale

    /// Zoom: moldura azul RGB(0,0,255) de 4 px e mapa recuado 4 px (TreeMapView.cpp:66-85).
    private static let zoomFrame: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let inset = model.isZoomed ? Self.zoomFrame : 0
            let mapSize = CGSize(width: max(0, geometry.size.width - 2 * inset), height: max(0, geometry.size.height - 2 * inset))
            ZStack(alignment: .topLeading) {
                Color(nsColor: .windowBackgroundColor)
                if model.isZoomed {
                    Rectangle().fill(Color(red: 0, green: 0, blue: 1))
                }
                ZStack(alignment: .topLeading) {
                    Color(nsColor: .windowBackgroundColor)
                    if let rendering = model.rendering {
                        Image(decorative: rendering.image, scale: displayScale)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: mapSize.width, height: mapSize.height)
                        Canvas { context, _ in
                            drawHighlights(context, rendering: rendering)
                        }
                        .frame(width: mapSize.width, height: mapSize.height)
                        .allowsHitTesting(false)
                    }
                    TreeMapEventView(
                        onClick: { point, clicks in
                            let pixel = CGPoint(x: point.x * displayScale, y: point.y * displayScale)
                            if clicks >= 2 { model.doubleClickTreemap(atPixel: pixel) } else { model.clickTreemap(atPixel: pixel) }
                        },
                        onMiddleClick: { model.zoomReset() },
                        onScroll: { delta, control in
                            if control {
                                if delta > 0 { model.zoomIn() } else { model.zoomOut() }
                            } else {
                                if delta > 0 { model.selectParent() } else { model.reselectChild() }
                            }
                        },
                        onHover: { point in
                            hover.item = point.flatMap { model.item(atPixel: CGPoint(x: $0.x * displayScale, y: $0.y * displayScale)) }
                        },
                        menu: { point in
                            let pixel = CGPoint(x: point.x * displayScale, y: point.y * displayScale)
                            if let item = model.item(atPixel: pixel), model.selected != item { model.select(item) }
                            return contextMenu()
                        }
                    )
                }
                .frame(width: mapSize.width, height: mapSize.height)
                .offset(x: inset, y: inset)

                // Painel escurecido enquanto lê (GraphView.cpp:300-323).
                if model.isScanning || model.index == nil {
                    Color.black.opacity(0.35)
                }
            }
            .onAppear { report(mapSize) }
            .onChange(of: mapSize) { report(mapSize) }
            .onChange(of: model.index == nil) { report(mapSize) }
        }
    }

    private func report(_ size: CGSize) {
        model.treemapResized(width: Int(size.width * displayScale), height: Int(size.height * displayScale))
    }

    /// Destaque: anel externo de 1·escala na cor de contraste (preto para o
    /// branco) e interno na cor de destaque (branco); lado ≤ 2·escala vira
    /// retângulo cheio; seleção única cresce 1 px. Hover: moldura de 1 px na cor
    /// do texto (TreeMapView.cpp:111-158, GraphView.cpp:221-240).
    private func drawHighlights(_ context: GraphicsContext, rendering: CushionTreemap.Rendering) {
        let scale = displayScale
        let rects = model.highlightRects().map {
            CGRect(x: $0.minX / scale, y: $0.minY / scale, width: $0.width / scale, height: $0.height / scale)
        }
        let single = rects.count == 1
        for var rect in rects {
            if single { rect = rect.insetBy(dx: -1, dy: -1) }
            if min(rect.width, rect.height) <= 2 {
                context.fill(Path(rect), with: .color(.white))
                continue
            }
            context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(.black), lineWidth: 1)
            context.stroke(Path(rect.insetBy(dx: 1.5, dy: 1.5)), with: .color(.white), lineWidth: 1)
        }
        if let hovered = hover.item, let raw = rendering.rects[hovered], raw.width > 0 {
            let rect = CGRect(x: raw.minX / scale, y: raw.minY / scale, width: raw.width / scale, height: raw.height / scale)
            context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(Color(nsColor: .textColor)), lineWidth: 1)
        }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let selected = model.selected
        func add(_ title: String, enabled: Bool = true, _ action: @escaping () -> Void) {
            let item = ActionMenuItem(title: title, action: action)
            item.isEnabled = enabled
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        add("Zoom In", enabled: model.canZoomIn) { model.zoomIn() }
        add("Zoom Out", enabled: model.isZoomed) { model.zoomOut() }
        add("Zoom Reset", enabled: model.isZoomed) { model.zoomReset() }
        menu.addItem(.separator())
        add("Select Parent") { model.selectParent() }
        add("Reselect Child") { model.reselectChild() }
        if let selected, selected >= 0 {
            menu.addItem(.separator())
            add("Open…") { model.open(selected) }
            add("Select in Finder…") { model.selectInFinder(selected) }
            add("Copy Path") { model.copyPath(selected) }
            menu.addItem(.separator())
            add("Delete (to Trash)", enabled: model.canTrash(selected)) { pendingTrash = selected }
        }
        return menu
    }
}

/// Mouse do treemap no nível do AppKit: clique/duplo clique, botão do meio,
/// roda (com Ctrl), hover e menu do botão direito.
private struct TreeMapEventView: NSViewRepresentable {
    let onClick: (CGPoint, Int) -> Void
    let onMiddleClick: () -> Void
    let onScroll: (CGFloat, Bool) -> Void
    let onHover: (CGPoint?) -> Void
    let menu: (CGPoint) -> NSMenu

    func makeNSView(context _: Context) -> EventView {
        let view = EventView()
        update(view)
        return view
    }

    func updateNSView(_ view: EventView, context _: Context) { update(view) }

    private func update(_ view: EventView) {
        view.onClick = onClick
        view.onMiddleClick = onMiddleClick
        view.onScroll = onScroll
        view.onHover = onHover
        view.menuProvider = menu
    }

    final class EventView: NSView {
        var onClick: ((CGPoint, Int) -> Void)?
        var onMiddleClick: (() -> Void)?
        var onScroll: ((CGFloat, Bool) -> Void)?
        var onHover: ((CGPoint?) -> Void)?
        var menuProvider: ((CGPoint) -> NSMenu)?
        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

        override func mouseDown(with event: NSEvent) { onClick?(point(event), event.clickCount) }
        override func otherMouseDown(with event: NSEvent) { if event.buttonNumber == 2 { onMiddleClick?() } }
        override func mouseMoved(with event: NSEvent) { onHover?(point(event)) }
        override func mouseExited(with _: NSEvent) { onHover?(nil) }

        /// Um passo da roda por gesto (o trackpad gera dezenas de eventos).
        private var scrollAccumulator: CGFloat = 0

        override func scrollWheel(with event: NSEvent) {
            if event.phase == .began { scrollAccumulator = 0 }
            scrollAccumulator += event.scrollingDeltaY
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 30 : 0.5
            guard abs(scrollAccumulator) >= threshold else { return }
            onScroll?(scrollAccumulator, event.modifierFlags.contains(.control))
            scrollAccumulator = 0
        }

        override func menu(for event: NSEvent) -> NSMenu? { menuProvider?(point(event)) }
    }
}

// MARK: - Barra de status

private struct StatusBar: View {
    @ObservedObject var model: DiskXRayViewModel
    @ObservedObject var hover: HoverState

    var body: some View {
        HStack(spacing: 0) {
            Text(model.statusText(hovered: hover.item))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().frame(height: 14).padding(.horizontal, 8)
            Text(model.statusSize(hovered: hover.item))
                .monospacedDigit()
                .frame(width: 220, alignment: .leading)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}
