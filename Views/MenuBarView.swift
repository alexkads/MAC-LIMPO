import SwiftUI

class MenuBarViewModel: ObservableObject {
    @Published var scanResults: [CleaningCategory: ScanResult] = [:]
    @Published var isScanning: [CleaningCategory: Bool] = [:]
    @Published var isCleaning = false
    @Published var cleaningProgress: Double = 0
    @Published var currentOperation = ""
    @Published var showProgress = false
    @Published var showResults = false
    @Published var lastResult: CleaningResult?
    @Published var currentCleaningCategory: CleaningCategory?
    
    @Published var totalDiskSpace: Int64 = 0
    @Published var usedDiskSpace: Int64 = 0
    
    // TEMPORÁRIO: Apenas serviços originais até adicionar os novos arquivos ao Xcode
    // Para adicionar os novos serviços:
    // 1. No Xcode: Project Navigator > Botão direito > Add Files...
    // 2. Selecione os 11 arquivos *CleaningService.swift criados
    // 3. Marque "Copy items if needed" e "Add to targets"
    // 4. Descomente as linhas abaixo e compile novamente
    
    let services: [CleaningCategory: CleaningService] = [
        .docker: DockerCleaningService(),
        .devPackages: DevPackagesCleaningService(),
        .tempFiles: TempFilesCleaningService(),
        .logs: LogsCleaningService(),
        .appCache: AppCacheCleaningService(),
        .xcodeCache: XcodeCacheCleaningService(),
        .iosSimulators: IOSSimulatorsCleaningService(),
        .downloads: DownloadsCleaningService(),
        .trash: TrashCleaningService(),
        .browserCache: BrowserCacheCleaningService(),
        .spotifyCache: SpotifyCacheCleaningService(),
        .slackCache: SlackCacheCleaningService(),
        .largeFiles: LargeFilesCleaningService(),
        .duplicateFiles: DuplicateFilesCleaningService(),
        .mailAttachments: MailAttachmentsCleaningService(),
        .messagesAttachments: MessagesAttachmentsCleaningService(),
        .ideCache: IDECacheCleaningService(),
        .androidSDK: AndroidSDKCleaningService(),
        .messagingApps: MessagingAppsCleaningService(),
        // New cleaning services
        .playwright: PlaywrightCleaningService(),
        .cargo: CargoCleaningService(),
        .homebrew: HomebrewCleaningService(),
        .terminalLogs: TerminalLogsCleaningService()
    ]
    
    init() {
        refreshDiskStats()
        scanAllCategories()
    }
    
    func refreshDiskStats() {
        let helper = FileSystemHelper.shared
        totalDiskSpace = helper.totalDiskSpace()
        usedDiskSpace = totalDiskSpace - helper.availableDiskSpace()
    }
    
    func scanAllCategories() {
        // Escaneia apenas categorias que têm serviços implementados
        for category in services.keys {
            scanCategory(category)
        }
    }
    
    @Published var scanningStatus: [CleaningCategory: String] = [:]
    
    // ... existing properties ...

    func scanCategory(_ category: CleaningCategory) {
        guard let service = services[category] else { return }
        
        isScanning[category] = true
        scanningStatus[category] = "Starting..."
        
        Task {
            let result = await service.scan(progress: { [weak self] status in
                Task { @MainActor in
                    self?.scanningStatus[category] = status
                }
            })
            
            await MainActor.run {
                scanResults[category] = result
                isScanning[category] = false
                scanningStatus[category] = nil
            }
        }
    }
    
    func cleanCategory(_ category: CleaningCategory) {
        guard let service = services[category] else { return }
        
        currentCleaningCategory = category
        showProgress = true
        cleaningProgress = 0
        currentOperation = "Preparing to clean..."
        
        Task {
            // Simula progresso
            await updateProgress(0.2, operation: "Scanning files...")
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            await updateProgress(0.5, operation: "Removing files...")
            
            let result = await service.clean()
            
            await updateProgress(1.0, operation: "Complete!")
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            await MainActor.run {
                showProgress = false
                lastResult = result
                showResults = true
                
                // Atualiza estatísticas
                refreshDiskStats()
                scanCategory(category)
            }
        }
    }
    
    func cleanAll() {
        Task {
            // Limpa apenas categorias que têm serviços implementados
            for category in services.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let service = services[category] else { continue }
                
                // Executa limpeza sequencialmente (não concorrente)
                await MainActor.run {
                    currentCleaningCategory = category
                    showProgress = true
                    cleaningProgress = 0
                    currentOperation = "Preparing to clean \(category.rawValue)..."
                }
                
                await updateProgress(0.3, operation: "Cleaning \(category.rawValue)...")
                let result = await service.clean()
                
                await updateProgress(1.0, operation: "Complete!")
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                await MainActor.run {
                    lastResult = result
                    refreshDiskStats()
                    scanCategory(category)
                }
                
                // Pequena pausa entre categorias
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            await MainActor.run {
                showProgress = false
                showResults = true
            }
        }
    }
    
    private func updateProgress(_ progress: Double, operation: String) async {
        await MainActor.run {
            cleaningProgress = progress
            currentOperation = operation
        }
    }
}

struct MenuBarView: View {
    @StateObject private var viewModel = MenuBarViewModel()
    @StateObject private var launchAtLoginService = LaunchAtLoginService()
    let onOpenTreemap: () -> Void
    
    init(onOpenTreemap: @escaping () -> Void = {}) {
        self.onOpenTreemap = onOpenTreemap
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("MAC-LIMPO")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            
                            Text("System Cleaner")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            onOpenTreemap()
                        }) {
                            Image(systemName: "square.grid.3x3.fill")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help("Disk Map")
                        
                        Button(action: {
                            viewModel.scanAllCategories()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help("Refresh scan")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Storage Stats
                    StorageStatsView(
                        usedSpace: viewModel.usedDiskSpace,
                        totalSpace: viewModel.totalDiskSpace
                    )
                    .padding(.horizontal, 20)
                    
                    // Cleaning Categories (apenas as implementadas)
                    VStack(spacing: 12) {
                        ForEach(Array(viewModel.services.keys).sorted(by: { $0.rawValue < $1.rawValue })) { category in
                            CleaningCategoryCard(
                                category: category,
                                estimatedSize: viewModel.scanResults[category]?.formattedSize ?? "...",
                                isScanning: viewModel.isScanning[category] ?? false,
                                scanningStatus: viewModel.scanningStatus[category],
                                action: {
                                    viewModel.cleanCategory(category)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Clean All Button
                    Button(action: {
                        viewModel.cleanAll()
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Clean All")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    
                    // Settings
                    VStack(spacing: 12) {
                        Toggle(isOn: $launchAtLoginService.isEnabled) {
                            Text("Launch at Login")
                                .font(.system(size: 14))
                        }
                        .toggleStyle(.switch)
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 10)
                    
                    // Quit Button
                    Button("Quit MAC-LIMPO") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                    .padding(.bottom, 12)
                }
            }
            
            // Progress Overlay
            if viewModel.showProgress, let category = viewModel.currentCleaningCategory {
                CleaningProgressView(
                    category: category,
                    isShowing: $viewModel.showProgress,
                    progress: viewModel.cleaningProgress,
                    currentOperation: viewModel.currentOperation
                )
            }
            
            // Results Overlay
            if viewModel.showResults, let result = viewModel.lastResult {
                ResultsView(
                    result: result,
                    isShowing: $viewModel.showResults
                )
            }
        }
        .frame(width: 420, height: 600)
    }
}
