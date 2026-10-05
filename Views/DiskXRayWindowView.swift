// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import AppKit
import MetalKit
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

    struct Tooltip: Equatable {
        let item: Int32
        /// Onde o ponteiro parou (pontos do mapa): a bandeira é fincada ali.
        let point: CGPoint
    }

    /// Tooltip 3D: aparece como um tooltip do sistema — só depois de o ponteiro
    /// ficar parado um instante —, fica fincado onde ele parou e some quando o
    /// ponteiro volta a se mexer.
    @Published private(set) var tooltip: Tooltip?
    private var dwell: Task<Void, Never>?
    private static let delay = Duration.milliseconds(700)

    func pointerMoved(to point: CGPoint?, item: Int32?) {
        // Tremida de poucos pontos não esconde a bandeira já aberta.
        if let tooltip, let point, hypot(point.x - tooltip.point.x, point.y - tooltip.point.y) <= 3 { return }
        hideTooltip()
        guard let point, let item else { return }
        dwell = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { self?.tooltip = Tooltip(item: item, point: point) }
        }
    }

    func showTooltip(_ tooltip: Tooltip) {
        dwell?.cancel()
        self.tooltip = tooltip
    }

    func hideTooltip() {
        dwell?.cancel()
        dwell = nil
        if tooltip != nil { tooltip = nil }
    }

    /// Tamanho atual do mapa (o gancho MACLIMPO_XRAY_HOVER mede nele).
    var mapSize = CGSize.zero
    /// Seleção que está com pino (e não contorno) — a folga do limiar lembra disto.
    var selectionPinned: Int32?
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
            Toggle(isOn: $model.showLabels) { Label("Labels", systemImage: "textformat") }
                .help("Names on the blocks and folder headers. Off: a clean map — rest the pointer on a block to see its name.")
            Toggle(isOn: $model.map3D) { Label("3D", systemImage: "cube") }
                .help("3D map: cushion relief lit on the GPU (Metal) — folders show as creases. Off: the flat 2D map.")
                .disabled(TreemapMetal.shared == nil)
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
        Button("Magnify Map to Fit") {
            model.select(item, reveal: false)
            model.magnifyToSelection()
        }
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
    /// Transição da caixa azul quando a seleção muda: de onde ela estava (no
    /// mapa, coordenadas unitárias) e quando começou.
    @State private var selectionMove: SelectionMove?

    private struct SelectionMove: Equatable {
        let from: CGRect?
        let start: Date
        /// Deslize até o novo lugar, depois o pulso em volta.
        static let slide = 0.35, total = 0.65
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    Color(red: model.treemapBackground.r, green: model.treemapBackground.g, blue: model.treemapBackground.b)
                    // Camadas como num jogo de mapa: o mapa inteiro por baixo, as
                    // anteriores e a atual por cima. Na pinça e no arrasto elas são
                    // esticadas/deslocadas até o novo render, e nada fica vazio.
                    // 3D: as camadas na GPU (formas vetoriais nítidas em qualquer zoom).
                    // 2D: bitmaps do CoreGraphics, recortados na parte visível.
                    if model.map3D, TreemapMetal.shared != nil {
                        MetalMapView(
                            layers: layers(covering: size).filter { $0.image == nil }
                                .map { TreemapMetal.Layer(rendering: $0, frame: imageFrame($0, in: size)) },
                            background: model.treemapBackground
                        )
                        .allowsHitTesting(false)
                    } else {
                        ForEach(layers(covering: size)) { rendering in
                            if let piece = visiblePiece(of: rendering, in: size) {
                                Image(decorative: piece.image, scale: 1)
                                    .resizable()
                                    .interpolation(.medium)
                                    .frame(width: piece.frame.width, height: piece.frame.height)
                                    .offset(x: piece.frame.minX, y: piece.frame.minY)
                            }
                        }
                    }
                    if let rendering = model.rendering {
                        // Quadro a quadro só durante a transição da seleção.
                        TimelineView(.animation(paused: selectionMove == nil)) { timeline in
                            Canvas { context, canvasSize in
                                highlight(context, size: canvasSize, rendering: rendering, now: timeline.date)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                    }
                    // O nome numa bandeirinha, como tooltip (2D e 3D); no 3D é o único
                    // texto — o relevo fica limpo.
                    if let tooltip = hover.tooltip,
                       let flag = TreemapFlags.tooltip(at: tooltip.point, in: size, sprite: {
                           model.flagSprite(for: tooltip.item, scale: displayScale, mirrored: $0)
                       }) {
                        Image(decorative: flag.sprite.image, scale: displayScale)
                            .frame(width: flag.frame.width, height: flag.frame.height)
                            .offset(x: flag.frame.minX, y: flag.frame.minY)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                    MapEventView(
                        isMagnified: model.isMagnified,
                        onClick: { point, clicks in
                            hover.hideTooltip()
                            let pixel = toPixel(point, in: size)
                            if clicks >= 2 { model.doubleClickTreemap(atPixel: pixel) } else { model.clickTreemap(atPixel: pixel) }
                        },
                        onMiddleClick: { model.zoomReset() },
                        onScroll: { delta, command in
                            if command {
                                if delta > 0 { model.zoomIn() } else { model.zoomOut() }
                            } else if delta > 0 { model.selectParent() } else { model.reselectChild() }
                        },
                        onMagnify: { factor, point in model.magnify(by: factor, around: anchor(point, in: size)) },
                        onSmartMagnify: { point in model.toggleMagnification(around: anchor(point, in: size)) },
                        onPan: { delta in
                            model.pan(by: CGSize(width: delta.width / max(1, size.width), height: delta.height / max(1, size.height)))
                        },
                        onHover: { point in
                            hover.item = point.flatMap { model.item(atPixel: toPixel($0, in: size)) }
                            hover.pointerMoved(to: point, item: hover.item)
                        },
                        menu: { point in
                            let pixel = toPixel(point, in: size)
                            if let item = model.item(atPixel: pixel), model.selected != item { model.select(item) }
                            return contextMenu()
                        }
                    )
                }
                .onAppear {
                    report(size)
                    simulateHover(in: size)
                }
                .onChange(of: size) { report(size) }
                .onChange(of: displayScale) { report(size) }
                // Zoom, arrasto ou troca de modo: o bloco saiu de baixo do ponteiro.
                .onChange(of: model.viewport) { hover.hideTooltip() }
                .onChange(of: model.selected) { old, _ in
                    // A caixa sai de onde estava (se a seleção anterior estava no mapa).
                    let from = old.flatMap { model.mapAnchor(for: $0) }.flatMap { model.unitRect(of: $0) }
                    selectionMove = SelectionMove(from: from, start: Date())
                }
                .task(id: selectionMove) {
                    guard selectionMove != nil else { return }
                    try? await Task.sleep(for: .seconds(SelectionMove.total))
                    if !Task.isCancelled { selectionMove = nil }
                }
                .onChange(of: model.map3D) { hover.hideTooltip() }
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
            Text(model.isMagnified ? "Drag or scroll to pan" : "Double-click to zoom in · pinch to magnify")
                .font(.caption)
                .foregroundStyle(.tertiary)
            magnifierControls
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Lupa: −, ampliação atual (clique volta ao mapa inteiro) e +.
    private var magnifierControls: some View {
        HStack(spacing: 2) {
            Button { model.magnify(by: 1 / 2, around: CGPoint(x: 0.5, y: 0.5), animated: true) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(!model.isMagnified)
            .help("Magnify Out (⌘−)")
            Button { model.resetMagnification() } label: {
                Text(magnificationText)
                    .monospacedDigit()
                    .frame(minWidth: 42)
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(!model.isMagnified)
            .help("Actual Size (⌘0)")
            Button { model.magnify(by: 2, around: CGPoint(x: 0.5, y: 0.5), animated: true) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(model.magnification >= DiskXRayViewModel.maxMagnification)
            .help("Magnify In (⌘+) — or pinch on the trackpad, scroll the mouse wheel")
            Button { model.magnifyToSelection() } label: { Image(systemName: "scope") }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canMagnifyToSelection)
                .help("Magnify to Selection (⌘↩) — down to a 1 KB file")
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    /// Desenvolvimento: MACLIMPO_XRAY_HOVER=<x>,<y> (fração do mapa) põe o cursor
    /// ali depois do scan, para capturar o tooltip 3D sem mouse.
    private func simulateHover(in _: CGSize) {
        guard let value = ProcessInfo.processInfo.environment["MACLIMPO_XRAY_HOVER"] else { return }
        let parts = value.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            // O tamanho de agora: no `onAppear` o mapa ainda não tem o tamanho final.
            let size = hover.mapSize
            let point = CGPoint(x: parts[0] * size.width, y: parts[1] * size.height)
            hover.item = model.item(atPixel: toPixel(point, in: size))
            if let item = hover.item { hover.showTooltip(.init(item: item, point: point)) }
        }
    }

    /// "2,5×", "64×", "1.800×" — sem casas decimais a partir de 10×.
    private var magnificationText: String {
        let value = model.magnification
        return value < 10
            ? Double(value).formatted(.number.precision(.fractionLength(0 ... 1))) + "×"
            : Int(value.rounded()).formatted() + "×"
    }

    /// Onde uma camada fica na view, em pontos. Ela foi desenhada para
    /// `rendering.viewport`; se o viewport já mudou (pinça ou arrasto em
    /// andamento), é esticada e deslocada até o novo render chegar.
    private func imageFrame(_ rendering: TreemapRenderer.Rendering, in size: CGSize) -> CGRect {
        let drawn = rendering.viewport
        let current = model.viewport
        return CGRect(
            x: (drawn.minX - current.minX) / current.width * size.width,
            y: (drawn.minY - current.minY) / current.height * size.height,
            width: drawn.width / current.width * size.width,
            height: drawn.height / current.height * size.height
        )
    }

    /// Da mais grossa para a mais nítida; para assim que uma cobre a tela toda.
    private func layers(covering size: CGSize) -> [TreemapRenderer.Rendering] {
        let candidates = ([model.baseLayer] + model.backdrop.sorted { $0.viewport.width > $1.viewport.width }
            + [model.rendering]).compactMap { $0 }
        var unique: [TreemapRenderer.Rendering] = []
        for layer in candidates where !unique.contains(where: { $0.id == layer.id }) { unique.append(layer) }
        let screen = CGRect(origin: .zero, size: size)
        // Só o que fica por cima da última camada que já cobre a tela inteira.
        if let cover = unique.lastIndex(where: { imageFrame($0, in: size).insetBy(dx: -0.5, dy: -0.5).contains(screen) }) {
            return Array(unique[cover...])
        }
        return unique
    }

    /// Só a parte visível da camada, recortada do bitmap. Esticar o bitmap inteiro
    /// a 1.000× passaria de bilhões de pontos; o recorte de poucos pixels não.
    private func visiblePiece(of rendering: TreemapRenderer.Rendering, in size: CGSize) -> (image: CGImage, frame: CGRect)? {
        let frame = imageFrame(rendering, in: size)
        let shown = frame.intersection(CGRect(origin: .zero, size: size))
        guard !shown.isNull, shown.width > 0, shown.height > 0 else { return nil }
        let xRatio = rendering.pixelSize.width / frame.width
        let yRatio = rendering.pixelSize.height / frame.height
        let crop = CGRect(x: (shown.minX - frame.minX) * xRatio, y: (shown.minY - frame.minY) * yRatio,
                          width: shown.width * xRatio, height: shown.height * yRatio)
            .integral
            .intersection(CGRect(origin: .zero, size: rendering.pixelSize))
        guard !crop.isNull, crop.width >= 1, crop.height >= 1, let image = rendering.image?.cropping(to: crop) else { return nil }
        return (image, CGRect(x: frame.minX + crop.minX / xRatio, y: frame.minY + crop.minY / yRatio,
                              width: crop.width / xRatio, height: crop.height / yRatio))
    }

    /// Ponto da view → pixel da camada atual (na escala com que foi desenhada).
    private func toPixel(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard let rendering = model.rendering else {
            return CGPoint(x: point.x * displayScale, y: point.y * displayScale)
        }
        let frame = imageFrame(rendering, in: size)
        return CGPoint(x: (point.x - frame.minX) * rendering.pixelSize.width / frame.width,
                       y: (point.y - frame.minY) * rendering.pixelSize.height / frame.height)
    }

    /// Ponto da view → fração da área visível do mapa (âncora da lupa).
    private func anchor(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x / max(1, size.width))), y: min(1, max(0, point.y / max(1, size.height))))
    }

    private func report(_ size: CGSize) {
        hover.mapSize = size
        model.treemapResized(width: Int(size.width * displayScale), height: Int(size.height * displayScale), scale: displayScale)
    }

    /// Contornos de hover e seleção. Ficam inteiros por dentro do bloco e da área
    /// visível: desenhados para fora, os blocos colados na borda do mapa tinham o
    /// contorno cortado pelo recorte arredondado (e os vizinhos cobriam o resto).
    private func highlight(_ context: GraphicsContext, size: CGSize, rendering: TreemapRenderer.Rendering, now: Date) {
        let frame = imageFrame(rendering, in: size)
        let xRatio = rendering.pixelSize.width / frame.width
        let yRatio = rendering.pixelSize.height / frame.height
        // Folga das bordas do mapa, que tem cantos arredondados de 10 pt.
        let visible = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        func outline(_ raw: CGRect, lineWidth: CGFloat) -> CGRect? {
            let item = CGRect(x: frame.minX + raw.minX / xRatio, y: frame.minY + raw.minY / yRatio,
                              width: raw.width / xRatio, height: raw.height / yRatio)
            let rect = item.intersection(visible).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            return rect.isNull || rect.width < 1 || rect.height < 1 ? nil : rect
        }
        func radius(_ rect: CGRect) -> CGFloat { min(5, min(rect.width, rect.height) / 4) }

        if let hovered = hover.item, let raw = rendering.rects[hovered], let rect = outline(raw, lineWidth: 1) {
            let path = Path(roundedRect: rect, cornerRadius: radius(rect))
            context.fill(path, with: .color(.white.opacity(0.12)))
            context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1)
        }
        guard let selected = model.selected, let geometry = model.selectionGeometry() else { return }
        let viewport = model.viewport
        func onScreen(_ unit: CGRect) -> CGRect {
            CGRect(x: (unit.minX - viewport.minX) / viewport.width * size.width,
                   y: (unit.minY - viewport.minY) / viewport.height * size.height,
                   width: unit.width / viewport.width * size.width,
                   height: unit.height / viewport.height * size.height)
        }
        let screen = onScreen(geometry.rect)

        // Transição: a caixa desliza (e muda de tamanho) do lugar antigo até o
        // novo, desacelerando; ao chegar, um pulso se expande e some em volta.
        if let move = selectionMove {
            let elapsed = now.timeIntervalSince(move.start)
            if let from = move.from, elapsed < SelectionMove.slide {
                let t = elapsed / SelectionMove.slide
                let eased = 1 - pow(1 - t, 3)
                let to = geometry.rect
                let unit = CGRect(x: from.minX + (to.minX - from.minX) * eased, y: from.minY + (to.minY - from.minY) * eased,
                                  width: from.width + (to.width - from.width) * eased,
                                  height: from.height + (to.height - from.height) * eased)
                let rect = onScreen(unit).intersection(visible).insetBy(dx: 2, dy: 2)
                if !rect.isNull, rect.width >= 1, rect.height >= 1 {
                    let path = Path(roundedRect: rect, cornerRadius: radius(rect))
                    context.stroke(path, with: .color(.black.opacity(0.45)), lineWidth: 4)
                    context.stroke(path, with: .color(.accentColor), lineWidth: 2.5)
                }
                return
            }
            let pulse = (elapsed - (move.from == nil ? 0 : SelectionMove.slide * 0.6)) / 0.4
            if pulse > 0, pulse < 1 {
                // Em volta do bloco, ou do ponto do pino se ele for minúsculo.
                let base = min(screen.width, screen.height) < 12
                    ? CGRect(x: screen.midX - 6, y: screen.midY - 6, width: 12, height: 12) : screen
                let ring = base.insetBy(dx: -CGFloat(pulse) * 14, dy: -CGFloat(pulse) * 14).intersection(visible)
                if !ring.isNull, ring.width >= 1, ring.height >= 1 {
                    context.stroke(Path(roundedRect: ring, cornerRadius: radius(ring) + CGFloat(pulse) * 6),
                                   with: .color(.accentColor.opacity(0.75 * (1 - pulse))), lineWidth: 3 * (1 - pulse) + 1)
                }
            }
        }
        // Pequeno demais para um contorno (arquivos de poucos KB, ou 0 KB, que não
        // têm área): pino. Com folga entre 8 e 12 pt, para não piscar no limiar
        // durante a pinça.
        let side = geometry.anchor == selected ? min(screen.width, screen.height) : 0
        let pinned = side < 8 || (side < 12 && hover.selectionPinned == selected)
        hover.selectionPinned = pinned ? selected : nil
        if pinned {
            let tip = CGPoint(x: screen.midX, y: screen.midY)
            guard visible.contains(tip) else { return }
            pin(context, at: tip, label: "\(model.name(selected)) · \(SizeFormat.bytes(model.size(selected)))", in: size)
        } else {
            // Halo escuro de 4 pt com o traço de destaque de 2,5 pt no meio: lê
            // sobre qualquer cor de bloco. Recortado à área visível antes de virar
            // Path (na lupa funda o retângulo passa de bilhões de pontos).
            let rect = screen.intersection(visible).insetBy(dx: 2, dy: 2)
            guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return }
            let path = Path(roundedRect: rect, cornerRadius: radius(rect))
            context.stroke(path, with: .color(.black.opacity(0.45)), lineWidth: 4)
            context.stroke(path, with: .color(.accentColor), lineWidth: 2.5)
        }
    }

    /// Pino de localização com a ponta em `tip` e o nome ao lado.
    private func pin(_ context: GraphicsContext, at tip: CGPoint, label: String, in size: CGSize) {
        let radius: CGFloat = 9
        let head = CGPoint(x: tip.x, y: tip.y - radius * 2.4)
        func drop(grow: CGFloat) -> Path {
            var path = Path(ellipseIn: CGRect(x: head.x - radius - grow, y: head.y - radius - grow,
                                              width: (radius + grow) * 2, height: (radius + grow) * 2))
            path.move(to: CGPoint(x: tip.x, y: tip.y + grow * 0.8))
            path.addLine(to: CGPoint(x: head.x - (radius + grow) * 0.78, y: head.y + (radius + grow) * 0.62))
            path.addLine(to: CGPoint(x: head.x + (radius + grow) * 0.78, y: head.y + (radius + grow) * 0.62))
            path.closeSubpath()
            return path
        }
        // Sombra no "chão" e o pino com borda branca.
        context.fill(Path(ellipseIn: CGRect(x: tip.x - 6, y: tip.y - 2, width: 12, height: 4)),
                     with: .color(.black.opacity(0.35)))
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 3, y: 1.5))
            layer.fill(drop(grow: 1.8), with: .color(.white))
            layer.fill(drop(grow: 0), with: .color(.accentColor))
            layer.fill(Path(ellipseIn: CGRect(x: head.x - 3.5, y: head.y - 3.5, width: 7, height: 7)), with: .color(.white))
        }

        // Etiqueta ao lado da cabeça (do outro lado se não couber na tela).
        let text = context.resolve(Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
        let measured = text.measure(in: CGSize(width: 280, height: 40))
        let width = min(measured.width, 280) + 14
        let height = measured.height + 6
        var bubble = CGRect(x: head.x + radius + 7, y: head.y - height / 2, width: width, height: height)
        if bubble.maxX > size.width - 4 { bubble.origin.x = head.x - radius - 7 - width }
        context.fill(Path(roundedRect: bubble, cornerRadius: height / 2), with: .color(.black.opacity(0.72)))
        context.draw(text, in: bubble.insetBy(dx: 7, dy: 3))
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
        add("Magnify to Fit") { model.magnifyToSelection() }
        add("Actual Size", enabled: model.isMagnified) { model.resetMagnification() }
        if selected >= 0 {
            menu.addItem(.separator())
            add("Move to Trash…", enabled: model.canTrash(selected)) { pendingTrash = selected }
        }
        return menu
    }
}

/// Mouse do mapa no nível do AppKit: clique/duplo clique, botão do meio, roda
/// (⌘ + roda dá zoom), hover e menu do botão direito. Lupa: pinça no trackpad,
/// ⌥ + roda, toque duplo com dois dedos; ampliado, rolar ou arrastar desloca.
private struct MapEventView: NSViewRepresentable {
    let isMagnified: Bool
    let onClick: (CGPoint, Int) -> Void
    let onMiddleClick: () -> Void
    let onScroll: (CGFloat, Bool) -> Void
    let onMagnify: (CGFloat, CGPoint) -> Void
    let onSmartMagnify: (CGPoint) -> Void
    let onPan: (CGSize) -> Void
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
        view.onMagnify = onMagnify
        view.onSmartMagnify = onSmartMagnify
        view.onPan = onPan
        view.isMagnified = isMagnified
        view.onHover = onHover
        view.menuProvider = menu
    }

    final class EventView: NSView {
        var onClick: ((CGPoint, Int) -> Void)?
        var onMiddleClick: (() -> Void)?
        var onScroll: ((CGFloat, Bool) -> Void)?
        var onMagnify: ((CGFloat, CGPoint) -> Void)?
        var onSmartMagnify: ((CGPoint) -> Void)?
        var onPan: ((CGSize) -> Void)?
        var isMagnified = false
        var onHover: ((CGPoint?) -> Void)?
        var menuProvider: ((CGPoint) -> NSMenu)?
        private var trackingArea: NSTrackingArea?
        private var scrollAccumulator: CGFloat = 0
        private var dragOrigin: CGPoint?
        private var isPanning = false
        /// Inércia do arraste, como num jogo de mapa: velocidade em pontos/s.
        private var velocity = CGSize.zero
        private var lastDrag: TimeInterval = 0
        private var glide: Timer?

        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                // Sempre, não só na janela-chave: o destaque segue o cursor como num mapa.
                rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

        /// O primeiro clique numa janela em segundo plano já vale (seleciona).
        override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

        // MARK: Gestos fora da janela-chave

        private var monitors: [Any] = []

        /// O macOS só entrega gestos do trackpad (pinça, toque duplo) à janela-chave
        /// — a rolagem vai para a janela sob o cursor, a pinça não. Num app de barra
        /// de menus a janela do X-Ray perde o foco a toda hora, e a pinça só voltava
        /// depois de um clique. Os monitores pegam o gesto quando o cursor está
        /// sobre o mapa e o evento iria para outro lugar.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            guard window != nil else { return }
            let mask: NSEvent.EventTypeMask = [.magnify, .smartMagnify]
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                nonisolated(unsafe) let event = event
                let handled = MainActor.assumeIsolated { self?.routeGesture(event) ?? false }
                return handled ? nil : event
            }) { monitors.append(local) }
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
                nonisolated(unsafe) let event = event
                MainActor.assumeIsolated { _ = self?.routeGesture(event) }
            }) { monitors.append(global) }
        }

        /// `true` se tratou o gesto: cursor sobre o mapa (janela visível e na frente
        /// naquele ponto), mas o evento não chegaria a esta view pelo caminho normal.
        private func routeGesture(_ event: NSEvent) -> Bool {
            guard let window, window.isVisible else { return false }
            if event.window === window, window.isKeyWindow { return false }
            let screenPoint = NSEvent.mouseLocation
            guard NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0) == window.windowNumber
            else { return false }
            let location = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
            guard bounds.contains(location) else { return false }
            switch event.type {
            case .magnify:
                stopGlide()
                onMagnify?(exp(event.magnification * 2), location)
            case .smartMagnify:
                onSmartMagnify?(location)
            default:
                return false
            }
            return true
        }

        override func mouseDown(with event: NSEvent) {
            stopGlide()
            dragOrigin = point(event)
            onClick?(point(event), event.clickCount)
        }

        /// Ampliado, arrastar desloca o mapa (o clique já selecionou o bloco).
        override func mouseDragged(with event: NSEvent) {
            guard isMagnified, let origin = dragOrigin else { return }
            let current = point(event)
            if !isPanning {
                guard hypot(current.x - origin.x, current.y - origin.y) >= 3 else { return }
                isPanning = true
                NSCursor.closedHand.push()
            }
            let delta = CGSize(width: current.x - origin.x, height: current.y - origin.y)
            onPan?(delta)
            dragOrigin = current
            // Média móvel: um único evento lento no fim não zera o embalo.
            let elapsed = max(event.timestamp - lastDrag, 1.0 / 240)
            let instant = CGSize(width: delta.width / elapsed, height: delta.height / elapsed)
            velocity = CGSize(width: velocity.width * 0.4 + instant.width * 0.6,
                              height: velocity.height * 0.4 + instant.height * 0.6)
            lastDrag = event.timestamp
        }

        override func mouseUp(with event: NSEvent) {
            if isPanning {
                NSCursor.pop()
                // Soltou ainda em movimento (sem parar antes): o mapa desliza.
                if event.timestamp - lastDrag < 0.05 { startGlide() }
            }
            isPanning = false
            dragOrigin = nil
        }

        private func startGlide() {
            guard hypot(velocity.width, velocity.height) > 120 else { return }
            let step = 1.0 / 60
            glide = Timer(timeInterval: step, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.glideStep(step) }
            }
            if let glide { RunLoop.main.add(glide, forMode: .common) }
        }

        private func glideStep(_ step: TimeInterval) {
            // Atrito: perde ~8% por quadro, para abaixo de 20 pt/s.
            velocity = CGSize(width: velocity.width * 0.92, height: velocity.height * 0.92)
            guard isMagnified, hypot(velocity.width, velocity.height) > 20 else { return stopGlide() }
            onPan?(CGSize(width: velocity.width * step, height: velocity.height * step))
        }

        private func stopGlide() {
            glide?.invalidate()
            glide = nil
            velocity = .zero
        }

        override func magnify(with event: NSEvent) {
            stopGlide()
            // Exponencial e um pouco acelerada: do disco inteiro a um arquivo de
            // 1 KB são ~2.000×, algumas pinças em vez de dezenas.
            onMagnify?(exp(event.magnification * 2), point(event))
        }

        override func smartMagnify(with event: NSEvent) {
            onSmartMagnify?(point(event))
        }
        override func otherMouseDown(with event: NSEvent) { if event.buttonNumber == 2 { onMiddleClick?() } }
        override func mouseMoved(with event: NSEvent) { onHover?(point(event)) }
        override func mouseExited(with _: NSEvent) { onHover?(nil) }

        override func scrollWheel(with event: NSEvent) {
            stopGlide()
            let precise = event.hasPreciseScrollingDeltas
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Roda do mouse (como no Google Maps) ou ⌥ + rolar no trackpad: zoom no cursor.
            if modifiers == .option || (!precise && modifiers.isEmpty) {
                let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
                onMagnify?(exp(delta * (precise ? 0.02 : 0.2)), point(event))
                return
            }
            if isMagnified, !event.modifierFlags.contains(.command) {
                // Ampliado, rolar desloca (dois dedos, como num mapa).
                let step: CGFloat = precise ? 1 : 12
                onPan?(CGSize(width: event.scrollingDeltaX * step, height: event.scrollingDeltaY * step))
                return
            }
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

// MARK: - Mapa 3D (Metal)

/// As camadas do mapa desenhadas pela GPU. Pausada: só redesenha quando o
/// SwiftUI muda as camadas ou as molduras delas (pinça, arrasto, render novo).
private struct MetalMapView: NSViewRepresentable {
    let layers: [TreemapMetal.Layer]
    let background: TreemapRenderer.RGB

    func makeNSView(context _: Context) -> MapMTKView {
        let view = MapMTKView(frame: .zero, device: TreemapMetal.shared?.device)
        view.colorPixelFormat = TreemapMetal.pixelFormat
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.framebufferOnly = true
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.layer?.isOpaque = true
        update(view)
        return view
    }

    func updateNSView(_ view: MapMTKView, context _: Context) { update(view) }

    private func update(_ view: MapMTKView) {
        view.layers = layers
        view.background = background
        view.needsDisplay = true
    }

    final class MapMTKView: MTKView, MetalSnapshotting {
        var layers: [TreemapMetal.Layer] = []
        var background = TreemapRenderer.RGB(r: 0, g: 0, b: 0)

        override var isFlipped: Bool { true }

        override func draw(_: NSRect) {
            TreemapMetal.shared?.draw(layers, background: background, in: self)
        }

        var snapshotBackground: TreemapRenderer.RGB { background }

        func snapshotImage() -> CGImage? {
            TreemapMetal.shared?.image(layers, background: background, viewSize: bounds.size,
                                       scale: window?.backingScaleFactor ?? 2)
        }
    }
}
