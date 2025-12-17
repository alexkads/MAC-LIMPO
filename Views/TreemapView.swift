import SwiftUI

struct TreemapView: View {
    @StateObject private var viewModel: TreemapViewModel
    @Binding var isShowing: Bool
    
    init(isShowing: Binding<Bool>, maxDepth: Int = 5) {
        self._isShowing = isShowing
        self._viewModel = StateObject(wrappedValue: TreemapViewModel(maxDepth: maxDepth))
    }
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    isShowing = false
                }
            
            // Main content
            VStack(spacing: 0) {
                // Header
                headerView
                
                if viewModel.isScanning {
                    // Scanning progress
                    scanningView
                } else if let currentNode = viewModel.currentNode {
                    // Treemap visualization
                    VStack(spacing: 0) {
                        // Breadcrumb navigation
                        breadcrumbView
                        
                        // Treemap canvas
                        treemapCanvas(for: currentNode)
                        
                        // Info panel
                        if let hovered = viewModel.hoveredNode {
                            infoPanel(for: hovered)
                        }
                    }
                } else {
                    // Directory selection
                    directorySelectionView
                }
            }
            .frame(width: 900, height: 700)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(16)
            .shadow(radius: 20)
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Map")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                if let current = viewModel.currentNode {
                    Text(current.formattedSize)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if viewModel.rootNode != nil && !viewModel.isScanning {
                Button(action: {
                    viewModel.reset()
                    viewModel.rootNode = nil
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("New scan")
            }
            
            Button(action: {
                isShowing = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Scanning View
    private var scanningView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView(value: viewModel.scanProgress) {
                Text("Scanning...")
                    .font(.system(size: 16, weight: .semibold))
            }
            .progressViewStyle(.linear)
            .frame(width: 400)
            
            Text(viewModel.scanStatus)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Directory Selection
    private var directorySelectionView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 8) {
                Text("Select a directory to scan")
                    .font(.system(size: 24, weight: .bold))
                
                Text("Choose a location to analyze disk space usage")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            // Grid layout with 2 columns
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(viewModel.getTopLevelDirectories(), id: \.path) { dir in
                    DirectoryCard(
                        name: dir.name,
                        path: dir.path,
                        icon: iconForDirectory(dir.name),
                        gradient: gradientForDirectory(dir.name)
                    ) {
                        viewModel.startScan(path: dir.path)
                    }
                }
            }
            .frame(width: 700)
            
            Spacer()
        }
        .padding(40)
    }
    
    // Helper functions for directory icons and colors
    private func iconForDirectory(_ name: String) -> String {
        switch name {
        case "Home": return "house.fill"
        case "Desktop": return "desktopcomputer"
        case "Documents": return "doc.text.fill"
        case "Downloads": return "arrow.down.circle.fill"
        case "Applications": return "app.fill"
        case "Library": return "books.vertical.fill"
        default: return "folder.fill"
        }
    }
    
    private func gradientForDirectory(_ name: String) -> LinearGradient {
        let colors: [Color]
        switch name {
        case "Home":
            colors = [Color(hex: "667eea"), Color(hex: "764ba2")]
        case "Desktop":
            colors = [Color(hex: "f093fb"), Color(hex: "f5576c")]
        case "Documents":
            colors = [Color(hex: "4facfe"), Color(hex: "00f2fe")]
        case "Downloads":
            colors = [Color(hex: "43e97b"), Color(hex: "38f9d7")]
        case "Applications":
            colors = [Color(hex: "fa709a"), Color(hex: "fee140")]
        case "Library":
            colors = [Color(hex: "30cfd0"), Color(hex: "330867")]
        default:
            colors = [.blue, .purple]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    // MARK: - Breadcrumb
    private var breadcrumbView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.element.id) { index, node in
                    Button(action: {
                        viewModel.navigateToBreadcrumb(node)
                    }) {
                        HStack(spacing: 4) {
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Text(node.name)
                                .font(.system(size: 12))
                                .foregroundColor(index == viewModel.breadcrumbs.count - 1 ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Treemap Canvas
    private func treemapCanvas(for node: FileNode) -> some View {
        GeometryReader { geometry in
            let rects = TreemapLayout.layout(
                nodes: node.children,
                in: CGRect(origin: .zero, size: geometry.size),
                depth: 0
            )
            
            Canvas { context, size in
                for rect in rects {
                    drawRect(rect, in: context)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Find hovered node
                        if let rect = rects.first(where: { $0.frame.contains(value.location) }) {
                            viewModel.hoveredNode = rect.node
                        }
                    }
                    .onEnded { value in
                        // Find clicked node
                        if let rect = rects.first(where: { $0.frame.contains(value.location) }) {
                            if rect.node.isDirectory && !rect.node.children.isEmpty {
                                viewModel.navigateToNode(rect.node)
                            }
                        }
                        viewModel.hoveredNode = nil
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func drawRect(_ rect: TreemapRect, in context: GraphicsContext) {
        let path = Path(rect.frame)
        
        // Fill
        context.fill(path, with: .color(rect.color))
        
        // Border
        context.stroke(
            path,
            with: .color(.white.opacity(0.3)),
            lineWidth: 1
        )
        
        // Label (se o retângulo for grande o suficiente)
        if rect.frame.width > 60 && rect.frame.height > 30 {
            let text = Text(rect.node.name)
                .font(.system(size: 10))
                .foregroundColor(.white)
            
            context.draw(
                text,
                at: CGPoint(
                    x: rect.frame.midX,
                    y: rect.frame.midY
                ),
                anchor: .center
            )
        }
    }
    
    // MARK: - Info Panel
    private func infoPanel(for node: FileNode) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(node.color)
                .frame(width: 20, height: 20)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                
                Text(node.path)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(node.formattedSize)
                    .font(.system(size: 12, weight: .semibold))
                
                if let parent = viewModel.currentNode {
                    Text(String(format: "%.1f%%", node.percentage(relativeTo: parent.totalSize)))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}
