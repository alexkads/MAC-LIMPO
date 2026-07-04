import AppKit
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

    /// Quando o usuário marca "não perguntar de novo", pulamos a confirmação nesta sessão.
    private var skipCleaningConfirmation = false

    /// Registry categoria → serviço. Ao adicionar um serviço, lembre de incluir o
    /// fonte em `sources:` do Package.swift (SPM não faz glob). Ver a skill
    /// `add-cleaning-service`.
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
        .adobeCache: AdobeCleaningService(),
        .mailAttachments: MailAttachmentsCleaningService(),
        .messagesAttachments: MessagesAttachmentsCleaningService(),
        .ideCache: IDECacheCleaningService(),
        .androidSDK: AndroidSDKCleaningService(),
        .messagingApps: MessagingAppsCleaningService(),
        // New cleaning services
        .playwright: PlaywrightCleaningService(),
        .cargo: CargoCleaningService(),
        .homebrew: HomebrewCleaningService(),
        .terminalLogs: TerminalLogsCleaningService(),
        // System deep clean
        .systemData: SystemDataCleaningService(),
        // New services for temp files and AI tools
        .varFolders: VarFoldersCleaningService(),
        .aiTools: AIToolsCleaningService(),
        // Niche services
        .creativeApps: CreativeAppsCleaningService(),
        .podcasts: PodcastsCleaningService(),
        .appLeftovers: AppLeftoversCleaningService(),
        // New Project Cleaner
        .development: ProjectCleaningService(),
        // New services: pnpm, Go, API Tools, Notion, Cypress
        .pnpm: PnpmCleaningService(),
        .goCache: GoCleaningService(),
        .devApiTools: DevApiToolsCleaningService(),
        .notionCache: NotionCleaningService(),
        .cypress: CypressCleaningService(),
        .tiktokLiveStudio: TikTokLiveStudioCleaningService()
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

    @Published var scanningStatus: [CleaningCategory: String] = [:]

    /// Máximo de scans simultâneos. Cada scan dispara processos `du`; sem limite,
    /// as ~35 categorias escaneavam todas de uma vez no launch, esgotando o thread
    /// pool cooperativo. 4 mantém a UI responsiva sem serializar demais.
    private let maxConcurrentScans = 4

    func scanAllCategories() {
        let categories = Array(services.keys)
        Task {
            await withTaskGroup(of: Void.self) { group in
                var next = 0
                let seed = min(maxConcurrentScans, categories.count)
                while next < seed {
                    let category = categories[next]; next += 1
                    group.addTask { await self.performScan(category) }
                }
                // À medida que cada scan termina, inicia o próximo (janela deslizante).
                while await group.next() != nil {
                    if next < categories.count {
                        let category = categories[next]; next += 1
                        group.addTask { await self.performScan(category) }
                    }
                }
            }
        }
    }

    func scanCategory(_ category: CleaningCategory) {
        Task { await performScan(category) }
    }

    /// Núcleo awaitable do scan de uma categoria; atualiza o estado no MainActor.
    private func performScan(_ category: CleaningCategory) async {
        guard let service = services[category] else { return }

        await MainActor.run {
            isScanning[category] = true
            scanningStatus[category] = "Starting..."
        }

        let result = await service.scan(progress: { [weak self] status in
            Task { @MainActor in self?.scanningStatus[category] = status }
        })

        await MainActor.run {
            scanResults[category] = result
            isScanning[category] = false
            scanningStatus[category] = nil
        }
    }

    /// Diálogo de confirmação antes de qualquer limpeza. Retorna `true` se pode prosseguir.
    /// A maioria das categorias envia os itens para a Lixeira (restaurável).
    private func confirmClean(_ categories: [CleaningCategory]) -> Bool {
        if skipCleaningConfirmation { return true }

        let totalSize = categories.reduce(Int64(0)) { $0 + (scanResults[$1]?.estimatedSize ?? 0) }
        let sizeText = FileSystemHelper.shared.formatBytes(totalSize)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSImage(systemSymbolName: "trash", accessibilityDescription: "Limpar")
        if categories.count == 1 {
            alert.messageText = "Limpar \(categories[0].rawValue)?"
        } else {
            alert.messageText = "Limpar \(categories.count) categorias?"
        }
        var body = """
        Cerca de \(sizeText) serão liberados. Sempre que possível, os itens vão para a \
        Lixeira e podem ser restaurados de lá.
        """
        if CleaningOptions.shared.aggressiveMode {
            body += "\n\n⚡️ Modo agressivo ligado: também remove caches grandes regeneráveis " +
                "(modelos de IA do Chrome, imagens Docker não usadas)."
        }
        alert.informativeText = body
        alert.addButton(withTitle: "Limpar")
        alert.addButton(withTitle: "Cancelar")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Não perguntar de novo nesta sessão"

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { skipCleaningConfirmation = true }
        return response == .alertFirstButtonReturn
    }

    func cleanCategory(_ category: CleaningCategory) {
        guard confirmClean([category]) else { return }

        // Se for System Data, verifica permissões primeiro
        if category == .systemData, !PermissionsHelper.hasFullDiskAccess() {
            PermissionsHelper.requestFullDiskAccess {
                // Depois de pedir permissão (ou pular), continua limpeza
                self.performCleanCategory(category)
            }
            return
        }

        performCleanCategory(category)
    }

    private func performCleanCategory(_ category: CleaningCategory) {
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
        guard confirmClean(Array(services.keys)) else { return }

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
    @ObservedObject private var cleaningOptions = CleaningOptions.shared
    let onOpenTreemap: () -> Void

    init(onOpenTreemap: @escaping () -> Void = {}) {
        self.onOpenTreemap = onOpenTreemap
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // FIXED HEADER SECTION
                VStack(spacing: 20) {
                    // Header Title & Buttons
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
                }
                .padding(.bottom, 10)

                // SCROLLABLE LIST SECTION
                ScrollView {
                    VStack(spacing: 20) {
                        // Cleaning Categories (apenas as implementadas)
                        // Cleaning Categories by Group
                        VStack(spacing: 20) {
                            ForEach(CleaningGroup.allCases) { group in
                                let categoriesInGroup = viewModel.services.keys
                                    .filter { $0.group == group }
                                    .sorted { $0.rawValue < $1.rawValue }

                                if !categoriesInGroup.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        // Group Header
                                        HStack {
                                            Image(systemName: group.icon)
                                                .font(.system(size: 14))
                                                .foregroundColor(.secondary)
                                            Text(group.rawValue)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 4)

                                        // Categories Grid
                                        VStack(spacing: 12) {
                                            ForEach(categoriesInGroup) { category in
                                                CleaningCategoryCard(
                                                    category: category,
                                                    estimatedSize: viewModel.scanResults[category]?
                                                        .formattedSize ?? "...",
                                                    isScanning: viewModel.isScanning[category] ?? false,
                                                    scanningStatus: viewModel.scanningStatus[category],
                                                    action: {
                                                        viewModel.cleanCategory(category)
                                                    }
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

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

                        // Settings
                        VStack(spacing: 12) {
                            Toggle(isOn: $launchAtLoginService.isEnabled) {
                                Text("Launch at Login")
                                    .font(.system(size: 14))
                            }
                            .toggleStyle(.switch)
                            .padding(.horizontal, 20)

                            Toggle(isOn: $cleaningOptions.aggressiveMode) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Aggressive cleaning")
                                        .font(.system(size: 14))
                                    Text(
                                        "Also clears large regenerable caches (Chrome AI models, all unused Docker images)"
                                    )
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .toggleStyle(.switch)
                            .padding(.horizontal, 20)
                        }

                        // Quit Button
                        Button("Quit MAC-LIMPO") {
                            NSApplication.shared.terminate(nil)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                        .padding(.bottom, 20)
                    }
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
        .onChange(of: cleaningOptions.aggressiveMode) { _ in
            // As estimativas mudam com o modo agressivo; re-escaneia para refletir.
            viewModel.scanAllCategories()
        }
    }
}
