import SwiftUI

/// Raio-X do disco: a conta inteira do APFS numa barra que fecha, e a lista
/// navegável do volume Data, onde cada linha diz o que é e quem limpa.
struct DiskXRayWindowView: View {
    @StateObject private var viewModel = DiskXRayViewModel()
    @State private var pendingTrash: XRayNode?
    let onClose: () -> Void

    private let format = FileSystemHelper.shared.formatBytes

    var body: some View {
        VStack(spacing: 0) {
            header
            if !viewModel.hasFullDiskAccess { fullDiskAccessBanner }
            if let overview = viewModel.overview {
                overviewSection(overview)
                Divider()
            }
            content
        }
        .frame(minWidth: 860, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { if viewModel.root == nil, !viewModel.isScanning { viewModel.startScan() } }
        .confirmationDialog(
            "Move \"\(pendingTrash?.name ?? "")\" to the Trash?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { node in
            Button("Move to Trash (\(format(node.size)))", role: .destructive) { viewModel.moveToTrash(node) }
            Button("Cancel", role: .cancel) {}
        } message: { node in
            Text("\(node.displayPath)\n\nYou can restore it from the Trash. Space is freed when the Trash is emptied.")
        }
        .alert(
            "Disk X-Ray",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rays")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Disk X-Ray").font(.title2.bold())
                Text("Where every byte of this disk goes — measured, not estimated.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isScanning {
                Button("Cancel") { viewModel.cancelScan() }
            } else {
                Button {
                    viewModel.startScan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }
            Button("Close") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)
            Text("Full Disk Access is off. Protected folders (Mail, Messages, app containers) can't be measured and show up as \"Not measured\".")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Grant Access…") { viewModel.openFullDiskAccessSettings() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Conta do disco

    private func overviewSection(_ overview: DiskOverview) -> some View {
        let segments = Self.segments(for: overview)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(format(overview.used)) used of \(format(overview.capacity))")
                    .font(.headline)
                Spacer()
                Text("\(format(overview.free)) free")
                    .font(.headline)
                    .foregroundStyle(.green)
            }

            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(2, geometry.size.width * segment.fraction(of: overview.capacity)))
                            .help("\(segment.name): \(format(segment.bytes))")
                    }
                }
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), alignment: .topLeading)], spacing: 10) {
                ForEach(segments) { segment in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(segment.color).frame(width: 10, height: 10).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(segment.name).font(.callout.weight(.semibold))
                                Spacer()
                                Text(format(segment.bytes)).font(.callout.monospacedDigit())
                            }
                            Text(segment.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    struct Segment: Identifiable {
        let id: String
        let name: String
        let bytes: Int64
        let color: Color
        let explanation: String

        func fraction(of total: Int64) -> CGFloat {
            total > 0 ? CGFloat(Double(bytes) / Double(total)) : 0
        }
    }

    static func segments(for overview: DiskOverview) -> [Segment] {
        let order: [VolumeRole] = [.data, .vm, .preboot, .system, .recovery, .update, .other]
        var result: [Segment] = []
        for role in order {
            for volume in overview.volumes where volume.role == role && volume.bytes > 0 {
                result.append(Segment(
                    id: volume.id, name: displayName(volume), bytes: volume.bytes,
                    color: color(for: role), explanation: role.explanation
                ))
            }
        }
        if overview.containerOverhead > 0 {
            result.append(Segment(
                id: "overhead", name: "APFS overhead", bytes: overview.containerOverhead,
                color: .secondary.opacity(0.6),
                explanation: "Container metadata and reserves outside any volume."
            ))
        }
        result.append(Segment(
            id: "free", name: "Free", bytes: overview.free, color: .green.opacity(0.35),
            explanation: "Unallocated space in the container."
        ))
        return result
    }

    private static func displayName(_ volume: VolumeSlice) -> String {
        switch volume.role {
        case .data: "Data (your files)"
        case .system: "macOS (System)"
        case .vm: "Swap (VM)"
        case .preboot: "Preboot"
        case .recovery: "Recovery"
        case .update: "Pending update"
        case .other: volume.name
        }
    }

    private static func color(for role: VolumeRole) -> Color {
        switch role {
        case .data: .purple
        case .vm: .teal
        case .preboot: .orange
        case .system: .gray
        case .recovery: .brown
        case .update: .yellow
        case .other: .pink
        }
    }

    // MARK: - Lista

    @ViewBuilder
    private var content: some View {
        if viewModel.isScanning {
            scanProgress
        } else if let current = viewModel.current {
            VStack(spacing: 0) {
                breadcrumbBar(current)
                Divider()
                list(for: current)
                Divider()
                detailPanel(viewModel.selected ?? current)
            }
        } else {
            VStack(spacing: 12) {
                Spacer()
                Text("Nothing measured yet").font(.title3)
                Button("Scan Disk") { viewModel.startScan() }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var scanProgress: some View {
        VStack(spacing: 14) {
            Spacer()
            let dataBytes = viewModel.overview?.dataVolume?.bytes ?? 0
            if dataBytes > 0 {
                ProgressView(value: min(1, Double(viewModel.measuredBytes) / Double(dataBytes)))
                    .frame(maxWidth: 420)
                Text("\(format(viewModel.measuredBytes)) of \(format(dataBytes)) measured")
                    .font(.headline.monospacedDigit())
            } else {
                ProgressView()
            }
            Text(Firmlinks.system().displayPath(viewModel.currentPath))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 560)
            if let started = viewModel.scanStarted {
                TimelineView(.periodic(from: started, by: 1)) { context in
                    Text("Walking the whole data volume… \(Int(context.date.timeIntervalSince(started)))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func breadcrumbBar(_ current: XRayNode) -> some View {
        HStack(spacing: 6) {
            Button {
                viewModel.goUp()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(viewModel.breadcrumbs.count <= 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.offset) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Button(index == 0 ? "Data volume" : node.name) { viewModel.open(node) }
                            .buttonStyle(.plain)
                            .font(.callout.weight(node === current ? .semibold : .regular))
                    }
                }
            }
            Spacer()
            Picker("", selection: $viewModel.mode) {
                ForEach(DiskXRayViewModel.Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
            .help("Largest files: the biggest files anywhere inside this folder")
            if let loading = viewModel.loadingNode, loading === current {
                ProgressView().controlSize(.small)
                Text("Measuring \(loading.name)…").font(.caption).foregroundStyle(.secondary)
            }
            Text(format(current.size)).font(.callout.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func list(for current: XRayNode) -> some View {
        let showingFiles = viewModel.mode == .largestFiles
        let children = showingFiles ? viewModel.largestFiles : (current.children ?? [])
        let largest = max(1, children.map(\.size).max() ?? 1)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(children) { node in
                    row(node, largest: largest)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if node.kind == .file { viewModel.quickLook(node) } else { viewModel.open(node) }
                        }
                        .simultaneousGesture(TapGesture().onEnded { viewModel.selected = node })
                        .contextMenu { contextMenu(for: node) }
                    Divider().padding(.leading, 52)
                }
                if children.isEmpty {
                    HStack(spacing: 8) {
                        if showingFiles ? viewModel.isFindingLargestFiles : viewModel.loadingNode === current {
                            ProgressView().controlSize(.small)
                        }
                        Text(emptyText(showingFiles: showingFiles, current: current))
                            .foregroundStyle(.secondary)
                    }
                    .padding(30)
                }
            }
        }
    }

    private func emptyText(showingFiles: Bool, current: XRayNode) -> String {
        if showingFiles {
            return viewModel.isFindingLargestFiles ? "Finding the largest files in \(current.name)…" : "No files"
        }
        return viewModel.loadingNode === current ? "Measuring…" : "Empty folder"
    }

    private func row(_ node: XRayNode, largest: Int64) -> some View {
        let hint = viewModel.hint(for: node)
        let capacity = viewModel.overview?.capacity ?? 0
        return HStack(spacing: 12) {
            Image(systemName: icon(for: node))
                .font(.system(size: 16))
                .foregroundStyle(iconColor(for: node))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(node.name).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    if node.isPartial {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                            .help("Some folders inside could not be read")
                    }
                    if let hint { hintChip(hint) }
                }
                if let subtitle = subtitle(for: node, hint: hint) {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule().fill(barColor(for: node, hint: hint))
                        .frame(width: max(3, geometry.size.width * CGFloat(Double(node.size) / Double(largest))))
                }
            }
            .frame(width: 160, height: 8)

            Text(format(node.size))
                .font(.callout.monospacedDigit().weight(.semibold))
                .frame(width: 84, alignment: .trailing)
            Text(capacity > 0 ? String(format: "%.1f%%", Double(node.size) / Double(capacity) * 100) : "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            Button {
                viewModel.open(node)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .opacity(node.isNavigable ? 1 : 0)
            .disabled(!node.isNavigable)
            .frame(width: 16)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(viewModel.selected === node ? Color.accentColor.opacity(0.15) : .clear)
    }

    private func hintChip(_ hint: XRayHint) -> some View {
        let (text, color): (String, Color) = switch hint.tone {
        case .cleanable: (hint.category.map { "Cleaner: \($0.rawValue)" } ?? "Cleanable", .green)
        case .manual: ("Manual", .orange)
        case .info: ("Info", .secondary)
        }
        return Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private func subtitle(for node: XRayNode, hint: XRayHint?) -> String? {
        switch node.kind {
        case .unmeasured: return "Protected areas and APFS metadata — see details below"
        case .looseFiles: return "Files directly in this folder"
        case .file where viewModel.mode == .largestFiles:
            return viewModel.relativeLocation(of: node)
        case .directory, .file: return hint?.label
        }
    }

    private func icon(for node: XRayNode) -> String {
        switch node.kind {
        case .directory: "folder.fill"
        case .file: "doc.fill"
        case .looseFiles: "doc.on.doc"
        case .unmeasured: "eye.slash"
        }
    }

    private func iconColor(for node: XRayNode) -> Color {
        switch node.kind {
        case .directory: .blue
        case .file: .secondary
        case .looseFiles: .secondary
        case .unmeasured: .orange
        }
    }

    private func barColor(for node: XRayNode, hint: XRayHint?) -> Color {
        if node.kind == .unmeasured { return .orange }
        switch hint?.tone {
        case .cleanable: return .green
        case .manual: return .orange
        default: return .purple
        }
    }

    @ViewBuilder
    private func contextMenu(for node: XRayNode) -> some View {
        if node.kind == .directory || node.kind == .file {
            if node.isNavigable { Button("Open") { viewModel.open(node) } }
            if node.kind == .file {
                Button("Quick Look") { viewModel.quickLook(node) }
                Button("Open with Default App") { viewModel.openWithDefaultApp(node) }
            }
            Button("Reveal in Finder") { viewModel.revealInFinder(node) }
            Button("Copy Path") { viewModel.copyPath(node) }
            if viewModel.canTrash(node) {
                Divider()
                Button("Move to Trash…", role: .destructive) { pendingTrash = node }
            }
        }
    }

    // MARK: - Detalhes

    private func detailPanel(_ node: XRayNode) -> some View {
        let hint = viewModel.hint(for: node)
        let capacity = viewModel.overview?.capacity ?? 0
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(node === viewModel.root ? "Data volume" : node.name).font(.headline)
                    if let hint { hintChip(hint) }
                }
                Text(node.displayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Group {
                    if node.kind == .unmeasured {
                        Text(viewModel.unmeasuredExplanation)
                    } else if let note = hint?.note {
                        Text(note)
                    } else if let hint, hint.tone == .cleanable, let category = hint.category {
                        Text("The \(category.rawValue) card in the menu bar cleans this.")
                    }
                    if node.isPartial {
                        Text("Some folders inside could not be read, so the real size may be larger.")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(format(node.size)).font(.title3.monospacedDigit().weight(.semibold))
                if capacity > 0 {
                    Text(String(format: "%.1f%% of disk", Double(node.size) / Double(capacity) * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if node.kind == .directory || node.kind == .file {
                    HStack {
                        if node.kind == .file {
                            Button("Quick Look") { viewModel.quickLook(node) }
                                .keyboardShortcut(.space, modifiers: [])
                        }
                        Button("Reveal") { viewModel.revealInFinder(node) }
                        if viewModel.canTrash(node) {
                            Button("Move to Trash…", role: .destructive) { pendingTrash = node }
                        }
                    }
                } else if node.kind == .unmeasured, !viewModel.hasFullDiskAccess {
                    Button("Grant Full Disk Access…") { viewModel.openFullDiskAccessSettings() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.secondary.opacity(0.06))
    }
}
