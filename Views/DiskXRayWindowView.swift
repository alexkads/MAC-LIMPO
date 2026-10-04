// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import AppKit
import SwiftUI

/// Disk X-Ray: resumo do disco por categoria, pastas e tipos de arquivo em
/// cima, mapa embaixo — tudo sincronizado.
struct DiskXRayWindowView: View {
    @StateObject private var model = DiskXRayViewModel()
    @StateObject private var hover = HoverState()
    @State private var pendingTrash: Int32?
    @Environment(\.colorScheme) private var colorScheme
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if model.index == nil {
                ScanProgressView(model: model)
            } else {
                SummaryHeader(model: model)
                Divider()
                VSplitView {
                    HSplitView {
                        BrowserPane(model: model, pendingTrash: $pendingTrash)
                            .frame(minWidth: 480, maxWidth: .infinity)
                        TypesPane(model: model)
                            .frame(minWidth: 260, idealWidth: 330, maxWidth: 460)
                    }
                    .frame(minHeight: 180, idealHeight: 300)
                    MapPane(model: model, hover: hover, pendingTrash: $pendingTrash)
                        .frame(minHeight: 220, idealHeight: 420)
                }
            }
            Divider()
            StatusBar(model: model, hover: hover)
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Disk X-Ray")
        .navigationSubtitle(model.isDriveScan ? "Macintosh HD" : model.name(model.index?.root ?? 0))
        .toolbar { XRayToolbar(model: model, pendingTrash: $pendingTrash) }
        .onAppear {
            applyColors()
            if model.index == nil, !model.isScanning { model.startScan() }
        }
        .onChange(of: colorScheme) {
            applyColors()
            model.scheduleRender()
        }
        .confirmationDialog(
            "Move to Trash?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { item in
            Button("Move to Trash", role: .destructive) { model.moveToTrash(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("\(model.path(item))\n\(SizeFormat.bytes(model.size(item))) — you can restore it from the Trash.")
        }
        .alert(
            "Disk X-Ray",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func applyColors() {
        let dark = colorScheme == .dark
        model.treemapDark = dark
        model.treemapBackground = dark
            ? TreemapRenderer.RGB(r: 0.11, g: 0.11, b: 0.12)
            : TreemapRenderer.RGB(r: 0.96, g: 0.96, b: 0.97)
    }
}

@MainActor
final class HoverState: ObservableObject {
    @Published var item: Int32?
}

private extension FileCategory {
    var color: Color { Color(red: rgb.r, green: rgb.g, blue: rgb.b) }
}

// MARK: - Barra de ferramentas

/// Itens da toolbar nativa da janela (NSToolbar via SwiftUI). Os mesmos
/// comandos, atalhos e regras de disponibilidade da barra anterior.
private struct XRayToolbar: ToolbarContent {
    @ObservedObject var model: DiskXRayViewModel
    @Binding var pendingTrash: Int32?

    private var selected: Int32? { model.selected.flatMap { $0 >= 0 ? $0 : nil } }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                Button { model.startScan(root: DiskXRayService.dataRoot) } label: {
                    Label("Macintosh HD", systemImage: "internaldrive")
                }
                Button { model.chooseFolderAndScan() } label: { Label("Choose Folder…", systemImage: "folder") }
            } label: {
                Label("Scan Target", systemImage: model.isDriveScan ? "internaldrive" : "folder")
            }
            .help("Choose what to scan")

            if model.isScanning {
                Button { model.cancelScan() } label: { Label("Stop", systemImage: "stop.fill") }
                    .help("Stop scanning")
            } else {
                Button { model.startScan(root: model.scanRoot) } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .help("Scan again (⌘R)")
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        ToolbarItem(placement: .principal) {
            Picker("Size", selection: $model.useLogicalSize) {
                Text("On Disk").tag(false)
                Text("Logical").tag(true)
            }
            .pickerStyle(.segmented)
            .help("On Disk: space actually used. Logical: size the files report (sparse files, compression).")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $model.showFreeSpace) { Label("Free Space", systemImage: "circle.dashed") }
                .help("Show free space in the map")
                .disabled(!model.isDriveScan)
            Toggle(isOn: $model.showUnaccounted) { Label("System", systemImage: "gearshape") }
                .help("Show space used by macOS and protected areas that the scan cannot read")
                .disabled(!model.isDriveScan)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { selected.map(model.quickLook) } label: { Label("Quick Look", systemImage: "eye") }
                .help("Quick Look (Space)")
                .keyboardShortcut(.space, modifiers: [])
                .disabled(selected == nil)
            Button { selected.map(model.revealInFinder) } label: { Label("Show in Finder", systemImage: "magnifyingglass") }
                .help("Show in Finder")
                .disabled(selected == nil)
            Button { selected.map(model.copyPath) } label: { Label("Copy Path", systemImage: "doc.on.doc") }
                .help("Copy Path")
                .disabled(selected == nil)
            Button { pendingTrash = selected } label: { Label("Move to Trash", systemImage: "trash") }
                .help("Move to Trash (⌘⌫)")
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!(selected.map(model.canTrash) ?? false))
        }
    }
}

// MARK: - Resumo

private struct SummaryHeader: View {
    @ObservedObject var model: DiskXRayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.isDriveScan ? model.name(model.index?.root ?? 0)
                    : ((model.name(model.index?.root ?? 0) as NSString).lastPathComponent))
                    .font(.title3.weight(.semibold))
                if model.isDriveScan, let overview = model.overview {
                    Text("\(SizeFormat.bytes(overview.used)) used · \(SizeFormat.bytes(overview.free)) free of \(SizeFormat.bytes(overview.capacity))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(SizeFormat.bytes(model.scannedBytes)) in \(SizeFormat.count(Int(model.index?.fileCount[0] ?? 0))) files")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let duration = model.scanDuration, let index = model.index {
                    Text("\(SizeFormat.count(index.count)) items · scanned in \(Int(duration.rounded()))s")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            CapacityBar(model: model)
                .frame(height: 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.categories) { stats in
                        CategoryChip(
                            stats: stats,
                            selected: model.typeFilter == .category(stats.category)
                        ) { model.setTypeFilter(.category(stats.category)) }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Barra da capacidade: categorias lidas, o resto do sistema e o livre.
private struct CapacityBar: View {
    @ObservedObject var model: DiskXRayViewModel

    var body: some View {
        GeometryReader { geometry in
            let capacity = model.isDriveScan ? model.overview?.capacity ?? model.scannedBytes : model.scannedBytes
            let total = Double(max(1, capacity))
            HStack(spacing: 1) {
                ForEach(model.categories) { stats in
                    Rectangle().fill(stats.category.color)
                        .frame(width: max(1, geometry.size.width * Double(stats.bytes) / total))
                        .help("\(stats.category.title): \(SizeFormat.bytes(stats.bytes))")
                }
                if model.isDriveScan, model.overview != nil {
                    Rectangle().fill(Color(red: 0.86, green: 0.64, blue: 0.28).opacity(0.8))
                        .frame(width: max(1, geometry.size.width * Double(model.unaccountedBytes) / total))
                        .help("System & Unaccounted: \(SizeFormat.bytes(model.unaccountedBytes))")
                    Rectangle().fill(Color.secondary.opacity(0.18))
                        .help("Free: \(SizeFormat.bytes(model.freeSpaceBytes))")
                }
            }
            .clipShape(Capsule())
        }
    }
}

private struct CategoryChip: View {
    let stats: DiskXRayViewModel.CategoryStats
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: stats.category.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(stats.category.color.gradient, in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(stats.category.title).font(.caption.weight(.medium)).lineLimit(1)
                    Text(SizeFormat.bytes(stats.bytes)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? stats.category.color.opacity(0.22) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(selected ? stats.category.color : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .help("\(stats.category.title): \(SizeFormat.count(stats.files)) files — click to highlight in the map")
    }
}

// MARK: - Progresso

private struct ScanProgressView: View {
    @ObservedObject var model: DiskXRayViewModel

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "rays")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.purple.gradient)
                .symbolEffect(.pulse, isActive: model.isScanning)
            if model.isScanning {
                if let progress = model.progress, progress.estimatedItems > 0 {
                    ProgressView(value: min(1, Double(progress.items) / Double(progress.estimatedItems)))
                        .frame(maxWidth: 360)
                    Text("\(SizeFormat.count(progress.items)) items · \(SizeFormat.bytes(progress.physicalBytes))")
                        .font(.headline.monospacedDigit())
                    Text(Firmlinks.system().displayPath(progress.currentPath))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 520)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Preparing…").foregroundStyle(.secondary)
                }
            } else {
                Button("Scan Macintosh HD") { model.startScan(root: DiskXRayService.dataRoot) }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pastas / maiores arquivos

private struct BrowserPane: View {
    @ObservedObject var model: DiskXRayViewModel
    @Binding var pendingTrash: Int32?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $model.tab) {
                    ForEach(DiskXRayViewModel.Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            if model.tab == .folders {
                FileTreeOutline(model: model, pendingTrash: $pendingTrash)
            } else {
                LargestFilesList(model: model, pendingTrash: $pendingTrash)
            }
        }
    }
}

private struct LargestFilesList: View {
    @ObservedObject var model: DiskXRayViewModel
    @Binding var pendingTrash: Int32?

    var body: some View {
        List(selection: Binding(get: { model.selected }, set: { if let item = $0 { model.select(item, reveal: false) } })) {
            ForEach(model.largestFiles, id: \.self) { item in
                HStack(spacing: 8) {
                    if let icon = model.icon(item) {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.name(item)).lineLimit(1).truncationMode(.middle)
                        Text(model.location(of: item)).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.head)
                    }
                    Spacer()
                    Text(SizeFormat.bytes(model.size(item))).monospacedDigit().foregroundStyle(.secondary)
                }
                .tag(item)
                .contextMenu { ItemMenu(model: model, item: item, pendingTrash: $pendingTrash) }
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: Int32.self) { _ in } primaryAction: { items in
            items.first.map(model.quickLook)
        }
    }
}

private struct ItemMenu: View {
    @ObservedObject var model: DiskXRayViewModel
    let item: Int32
    @Binding var pendingTrash: Int32?

    var body: some View {
        Button("Quick Look") { model.quickLook(item) }
        Button("Open") { model.open(item) }
        Button("Show in Finder") { model.revealInFinder(item) }
        Button("Copy Path") { model.copyPath(item) }
        Divider()
        Button("Zoom Map Here") { model.zoom(into: item) }
        Divider()
        Button("Move to Trash…", role: .destructive) { pendingTrash = item }
            .disabled(!model.canTrash(item))
    }
}

// MARK: - Tipos de arquivo

private struct TypesPane: View {
    @ObservedObject var model: DiskXRayViewModel

    var body: some View {
        List {
            ForEach(model.categories) { stats in
                DisclosureGroup {
                    ForEach(stats.extensions.prefix(40), id: \.self) { ext in
                        extensionRow(ext, category: stats.category)
                    }
                } label: {
                    categoryRow(stats)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func categoryRow(_ stats: DiskXRayViewModel.CategoryStats) -> some View {
        let selected = model.typeFilter == .category(stats.category)
        return HStack(spacing: 8) {
            Image(systemName: stats.category.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(stats.category.color.gradient, in: RoundedRectangle(cornerRadius: 5))
            Text(stats.category.title).fontWeight(selected ? .semibold : .regular).lineLimit(1)
            Spacer()
            Text(SizeFormat.bytes(stats.bytes)).monospacedDigit().foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.setTypeFilter(.category(stats.category)) }
    }

    private func extensionRow(_ ext: Int32, category: FileCategory) -> some View {
        let selected = model.typeFilter == .fileExtension(ext)
        return HStack(spacing: 8) {
            Image(nsImage: model.extensionIcon(ext)).resizable().frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.extensionName(ext)).fontWeight(selected ? .semibold : .regular)
                Text(model.extensionDescription(ext)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(SizeFormat.bytes(model.extensionBytes(ext))).monospacedDigit()
                Text("\(SizeFormat.count(model.extensionFiles(ext))) files").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
        .background(selected ? category.color.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { model.setTypeFilter(.fileExtension(ext)) }
    }
}

// MARK: - Mapa

private struct MapPane: View {
    @ObservedObject var model: DiskXRayViewModel
    @ObservedObject var hover: HoverState
    @Binding var pendingTrash: Int32?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    Color(nsColor: .windowBackgroundColor)
                    if let rendering = model.rendering {
                        // Exibe na escala em que foi desenhado: se a janela mudou de
                        // tela, um novo render chega em seguida (report abaixo).
                        Image(decorative: rendering.image, scale: rendering.scale)
                            .interpolation(.medium)
                        Canvas { context, _ in highlight(context, rendering: rendering) }
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                    }
                    MapEventView(
                        onClick: { point, clicks in
                            let pixel = toPixel(point)
                            if clicks >= 2 { model.doubleClickTreemap(atPixel: pixel) } else { model.clickTreemap(atPixel: pixel) }
                        },
                        onMiddleClick: { model.zoomReset() },
                        onScroll: { delta, command in
                            if command {
                                if delta > 0 { model.zoomIn() } else { model.zoomOut() }
                            } else if delta > 0 { model.selectParent() } else { model.reselectChild() }
                        },
                        onHover: { point in
                            hover.item = point.flatMap { model.item(atPixel: toPixel($0)) }
                        },
                        menu: { point in
                            let pixel = toPixel(point)
                            if let item = model.item(atPixel: pixel), model.selected != item { model.select(item) }
                            return contextMenu()
                        }
                    )
                }
                .onAppear { report(size) }
                .onChange(of: size) { report(size) }
                .onChange(of: displayScale) { report(size) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding([.horizontal, .bottom], 10)
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            Button { model.zoomOut() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .disabled(!model.isZoomed)
                .help("Up one level")
            ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { position, item in
                if position > 0 {
                    Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
                }
                Button(model.name(item)) { model.zoom(into: item) }
                    .buttonStyle(.borderless)
                    .fontWeight(item == model.zoomItem ? .semibold : .regular)
                    .lineLimit(1)
            }
            Spacer()
            if model.isRendering { ProgressView().controlSize(.mini) }
            Text("Double-click to zoom in")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Ponto da view → pixel do bitmap atual (na escala com que foi desenhado).
    private func toPixel(_ point: CGPoint) -> CGPoint {
        let scale = model.rendering?.scale ?? displayScale
        return CGPoint(x: point.x * scale, y: point.y * scale)
    }

    private func report(_ size: CGSize) {
        model.treemapResized(width: Int(size.width * displayScale), height: Int(size.height * displayScale), scale: displayScale)
    }

    private func highlight(_ context: GraphicsContext, rendering: TreemapRenderer.Rendering) {
        let scale = rendering.scale
        func viewRect(_ raw: CGRect) -> CGRect {
            CGRect(x: raw.minX / scale, y: raw.minY / scale, width: raw.width / scale, height: raw.height / scale)
        }
        if let hovered = hover.item, let raw = rendering.rects[hovered], raw.width > 0 {
            let rect = viewRect(raw).insetBy(dx: 0.5, dy: 0.5)
            context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(.white.opacity(0.12)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(.white.opacity(0.7)), lineWidth: 1)
        }
        if let selected = model.selected, let raw = rendering.rects[selected], raw.width > 0 {
            let rect = viewRect(raw).insetBy(dx: -1, dy: -1)
            let path = Path(roundedRect: rect, cornerRadius: 5)
            context.stroke(path, with: .color(.black.opacity(0.45)), lineWidth: 4)
            context.stroke(path, with: .color(.accentColor), lineWidth: 2.5)
        }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, enabled: Bool = true, _ action: @escaping () -> Void) {
            let item = ActionMenuItem(title: title, action: action)
            item.isEnabled = enabled
            menu.addItem(item)
        }
        guard let selected = model.selected else { return menu }
        if selected >= 0 {
            add("Quick Look") { model.quickLook(selected) }
            add("Open") { model.open(selected) }
            add("Show in Finder") { model.revealInFinder(selected) }
            add("Copy Path") { model.copyPath(selected) }
            menu.addItem(.separator())
        }
        add("Zoom In") { model.zoomIn() }
        add("Zoom Out", enabled: model.isZoomed) { model.zoomOut() }
        add("Back to Top", enabled: model.isZoomed) { model.zoomReset() }
        if selected >= 0 {
            menu.addItem(.separator())
            add("Move to Trash…", enabled: model.canTrash(selected)) { pendingTrash = selected }
        }
        return menu
    }
}

/// Mouse do mapa no nível do AppKit: clique/duplo clique, botão do meio, roda
/// (⌘ + roda dá zoom), hover e menu do botão direito.
private struct MapEventView: NSViewRepresentable {
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
        private var scrollAccumulator: CGFloat = 0

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

        override func scrollWheel(with event: NSEvent) {
            if event.phase == .began { scrollAccumulator = 0 }
            scrollAccumulator += event.scrollingDeltaY
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 30 : 0.5
            guard abs(scrollAccumulator) >= threshold else { return }
            onScroll?(scrollAccumulator, event.modifierFlags.contains(.command))
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
        HStack(spacing: 12) {
            Text(model.statusText(hovered: hover.item))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            Text(model.statusSize(hovered: hover.item))
                .monospacedDigit()
                .fontWeight(.medium)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}
