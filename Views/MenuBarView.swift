import AppKit
import SwiftUI

/// Pedido de confirmação de limpeza mostrado inline no popover.
struct ConfirmationRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let onConfirm: () -> Void
}

@MainActor
class MenuBarViewModel: ObservableObject {
    @Published var scanResults: [CleaningCategory: ScanResult] = [:]
    @Published var isScanning: [CleaningCategory: Bool] = [:]
    /// Categorias com limpeza em andamento. Limpezas individuais rodam em
    /// paralelo (cada card mostra o próprio spinner) — o overlay modal ficou
    /// só para o "Clean All".
    @Published var cleaningCategories: Set<CleaningCategory> = []
    @Published var cleaningProgress: Double = 0
    @Published var currentOperation = ""
    @Published var showProgress = false
    @Published var showResults = false

    /// Pedido de confirmação exibido inline (dentro do popover), no lugar do antigo
    /// `NSAlert` — que roubava o foco e fechava o popover. `nil` = nada pendente.
    @Published var confirmationRequest: ConfirmationRequest?
    @Published var lastResult: CleaningResult?
    @Published var currentCleaningCategory: CleaningCategory?

    @Published var totalDiskSpace: Int64 = 0
    @Published var usedDiskSpace: Int64 = 0

    /// Quando o usuário marca "não perguntar de novo", pulamos a confirmação nesta sessão.
    private var skipCleaningConfirmation = false

    /// Atualiza automaticamente apenas o card de Storage de hora em hora.
    private var diskStatsTimer: Timer?

    /// Shared registry used by the UI, App Intents and Apple Intelligence.
    let services = CleaningServiceRegistry.shared.services

    init() {
        refreshDiskStats()
        scanAllCategories()
        startDiskStatsTimer()
    }

    func refreshDiskStats() {
        let helper = FileSystemHelper.shared
        totalDiskSpace = helper.totalDiskSpace()
        usedDiskSpace = totalDiskSpace - helper.availableDiskSpace()
    }

    /// Agenda a atualização automática do card de Storage de hora em hora.
    /// Só recalcula o espaço em disco — não dispara os scans das categorias.
    private func startDiskStatsTimer() {
        diskStatsTimer?.invalidate()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDiskStats()
            }
        }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        diskStatsTimer = timer
    }

    @Published var scanningStatus: [CleaningCategory: String] = [:]

    /// Evita que atualizações disparadas enquanto um scan ainda está em andamento
    /// criem outra árvore de Tasks. Isso era especialmente problemático nas
    /// categorias com muitos paths: cada rodada extra ficava esperando no
    /// `duGate` e o card permanecia girando por tempo indefinido.
    private var scanAllInProgress = false
    private var scanAllRequestedWhileRunning = false
    /// Categorias pedidas individualmente (ex.: ao fim de uma limpeza) enquanto o
    /// scan completo rodava. Reescaneia só elas depois — antes, qualquer pedido
    /// individual virava um scan completo de todas as categorias.
    private var pendingCategoryScans: Set<CleaningCategory> = []

    /// Prazo por categoria. Um scan que não termina deixava `scanAllInProgress`
    /// verdadeiro para sempre: o refresh passava a ser ignorado e só reabrir o
    /// app destravava.
    static let scanDeadline: TimeInterval = 420
    /// Scan mais lento que isto é registrado, para dar pista de qual categoria trava.
    private static let slowScanThreshold: TimeInterval = 60

    /// Máximo de scans simultâneos, dimensionado pelos núcleos do Mac. Cada scan
    /// mede tamanhos via `du` no pool do GCD (não trava o pool cooperativo), então
    /// podemos usar todos os cores. Limitado a 8 para não saturar o I/O do disco.
    private let maxConcurrentScans = min(8, max(2, ProcessInfo.processInfo.activeProcessorCount))

    func scanAllCategories() {
        // A UI pode chamar este método pelo botão de refresh, pela troca do modo
        // agressivo ou depois de uma limpeza. Não sobreponha rodadas; basta
        // garantir uma única atualização adicional ao terminar a atual.
        guard !scanAllInProgress else {
            scanAllRequestedWhileRunning = true
            return
        }

        scanAllInProgress = true
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

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.scanAllInProgress = false

                if self.scanAllRequestedWhileRunning {
                    self.scanAllRequestedWhileRunning = false
                    self.pendingCategoryScans.removeAll()
                    self.scanAllCategories()
                } else if !self.pendingCategoryScans.isEmpty {
                    let pending = self.pendingCategoryScans
                    self.pendingCategoryScans.removeAll()
                    for category in pending { self.scanCategory(category) }
                }
            }
        }
    }

    func scanCategory(_ category: CleaningCategory) {
        // Um scan completo já inclui esta categoria. Se ele estiver rodando,
        // adia só esta categoria em vez de iniciar uma segunda medição dos
        // mesmos diretórios (ou de refazer o scan completo).
        guard !scanAllInProgress else {
            pendingCategoryScans.insert(category)
            return
        }

        // Limpezas individuais reescaneiam a categoria ao terminar. Protege
        // contra dois callbacks chegando antes de o primeiro marcar o estado.
        guard !(isScanning[category] ?? false) else { return }
        Task { await performScan(category) }
    }

    /// Núcleo awaitable do scan de uma categoria; atualiza o estado no MainActor.
    private func performScan(_ category: CleaningCategory) async {
        guard let service = services[category] else { return }

        await MainActor.run {
            isScanning[category] = true
            scanningStatus[category] = "Starting..."
        }

        let started = Date()
        let scanned = await withDeadline(Self.scanDeadline) { [weak self] in
            await service.scan(progress: { status in
                Task { @MainActor in self?.scanningStatus[category] = status }
            })
        }
        let elapsed = Date().timeIntervalSince(started)

        if scanned == nil {
            logger.log("Scan de \(category.rawValue) excedeu \(Int(Self.scanDeadline))s e foi abandonado", level: .error)
        } else if elapsed > Self.slowScanThreshold {
            logger.log("Scan de \(category.rawValue) demorou \(Int(elapsed))s", level: .warning)
        }

        await MainActor.run {
            // No prazo estourado mantém a última medição boa; sem ela, mostra zero.
            if let scanned {
                scanResults[category] = scanned
            } else if scanResults[category] == nil {
                scanResults[category] = ScanResult(
                    category: category, estimatedSize: 0, itemCount: 0, items: ["Scan timed out — refresh to retry"]
                )
            }
            isScanning[category] = false
            scanningStatus[category] = nil
        }
    }

    /// Prepara uma confirmação inline antes de limpar. Se o usuário já pediu para não
    /// perguntar de novo nesta sessão, executa `onConfirm` direto. Caso contrário,
    /// publica um `ConfirmationRequest` que a UI mostra dentro do próprio popover —
    /// assim ele não fecha e o progresso segue visível ali mesmo.
    private func requestConfirmation(_ categories: [CleaningCategory], onConfirm: @escaping () -> Void) {
        if skipCleaningConfirmation {
            onConfirm()
            return
        }

        let totalSize = categories.reduce(Int64(0)) { $0 + (scanResults[$1]?.estimatedSize ?? 0) }
        let sizeText = FileSystemHelper.shared.formatBytes(totalSize)
        let title = categories.count == 1
            ? "Limpar \(categories[0].rawValue)?"
            : "Limpar \(categories.count) categorias?"
        var body = """
        Cerca de \(sizeText) serão liberados. Sempre que possível, os itens vão para a \
        Lixeira e podem ser restaurados de lá.
        """
        if CleaningOptions.shared.aggressiveMode {
            body += "\n\n⚡️ Modo agressivo ligado: também remove caches grandes regeneráveis " +
                "(modelos de IA do Chrome, imagens Docker não usadas)."
        }
        confirmationRequest = ConfirmationRequest(title: title, message: body, onConfirm: onConfirm)
    }

    /// Confirma a limpeza pendente. `dontAskAgain` equivale ao antigo botão de supressão.
    func confirmPendingClean(dontAskAgain: Bool) {
        if dontAskAgain { skipCleaningConfirmation = true }
        let request = confirmationRequest
        confirmationRequest = nil
        request?.onConfirm()
    }

    func cancelPendingClean() {
        confirmationRequest = nil
    }

    func cleanCategory(_ category: CleaningCategory) {
        requestConfirmation([category]) { [weak self] in
            guard let self else { return }
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
    }

    /// Resultados das limpezas individuais em andamento. Quando a última
    /// termina, viram um único ResultsView (combinado se houve mais de uma).
    private var pendingResults: [CleaningResult] = []
    private var concurrentCleanStart: Date?

    private func performCleanCategory(_ category: CleaningCategory) {
        guard let service = services[category] else { return }
        // Segundo clique na mesma categoria enquanto ela limpa: ignora.
        guard !cleaningCategories.contains(category) else { return }

        if cleaningCategories.isEmpty {
            concurrentCleanStart = Date()
        }
        cleaningCategories.insert(category)

        Task {
            let result = await service.clean()

            await MainActor.run {
                cleaningCategories.remove(category)
                pendingResults.append(result)

                // Re-escaneia a categoria limpa sem esperar as demais.
                scanCategory(category)

                // Só mostra resultados quando a última limpeza simultânea acabar.
                guard cleaningCategories.isEmpty else { return }
                let results = pendingResults
                pendingResults = []
                let duration = Date().timeIntervalSince(concurrentCleanStart ?? Date())
                lastResult = results.count == 1
                    ? results[0]
                    : Self.combinedResult(results, fallbackCategory: category, executionTime: duration)
                showResults = true
                refreshDiskStats()
            }
        }
    }

    /// Consolida vários CleaningResults num só (soma bytes/arquivos, junta erros).
    /// Sucesso se nada falhou OU se, apesar de algum erro pontual, houve espaço
    /// liberado — assim 18 GB limpos não viram "Failed" por um erro isolado.
    private static func combinedResult(
        _ results: [CleaningResult],
        fallbackCategory: CleaningCategory,
        executionTime: TimeInterval
    ) -> CleaningResult {
        let totalBytes = results.reduce(0) { $0 + $1.bytesRemoved }
        let allErrors = results.flatMap(\.errors)
        return CleaningResult(
            category: results.first?.category ?? fallbackCategory,
            bytesRemoved: totalBytes,
            filesRemoved: results.reduce(0) { $0 + $1.filesRemoved },
            errors: allErrors,
            executionTime: executionTime,
            success: allErrors.isEmpty || totalBytes > 0
        )
    }

    /// Máximo de limpezas simultâneas. Menor que o de scan: deletar é mais pesado
    /// de I/O e alguns services rodam comandos de sistema (Docker, purge).
    private let maxConcurrentCleans = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount))

    func cleanAll() {
        requestConfirmation(Array(services.keys)) { [weak self] in
            self?.startCleanAll()
        }
    }

    private func startCleanAll() {
        // Exclui categorias que já estão sendo limpas individualmente agora —
        // limpar o mesmo alvo duas vezes ao mesmo tempo só gera erros benignos.
        let categories = services.keys
            .filter { !cleaningCategories.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
        let total = categories.count

        Task {
            let startTime = Date()
            await MainActor.run {
                currentCleaningCategory = categories.first
                showProgress = true
                cleaningProgress = 0
                currentOperation = "Cleaning \(total) categories..."
            }

            // Limpa em paralelo com janela deslizante (respeita o teto de concorrência).
            var results: [CleaningResult] = []
            await withTaskGroup(of: CleaningResult?.self) { group in
                var next = 0
                let seed = min(maxConcurrentCleans, total)
                while next < seed {
                    let category = categories[next]; next += 1
                    group.addTask { await self.services[category]?.clean() }
                }
                while let finished = await group.next() {
                    if let finished { results.append(finished) }
                    let done = results.count
                    await MainActor.run {
                        cleaningProgress = Double(done) / Double(total)
                        currentOperation = "Cleaning… \(done)/\(total) categorias"
                        if let finished { currentCleaningCategory = finished.category }
                    }
                    if next < categories.count {
                        let category = categories[next]; next += 1
                        group.addTask { await self.services[category]?.clean() }
                    }
                }
            }

            // Resultado combinado (ResultsView mostra total liberado/arquivos/tempo).
            let combined = Self.combinedResult(
                results,
                fallbackCategory: categories.first ?? .trash,
                executionTime: Date().timeIntervalSince(startTime)
            )

            await MainActor.run {
                showProgress = false
                lastResult = combined
                showResults = true
                refreshDiskStats()
                scanAllCategories()
            }
        }
    }
}

struct MenuBarView: View {
    @StateObject private var viewModel = MenuBarViewModel()
    @StateObject private var launchAtLoginService = LaunchAtLoginService()
    @ObservedObject private var cleaningOptions = CleaningOptions.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var searchText = ""
    @State private var intelligenceInsight: String?
    @State private var intelligenceStatus: AppleIntelligenceAvailability?
    @State private var isGeneratingInsight = false
    let onOpenTreemap: () -> Void

    init(onOpenTreemap: @escaping () -> Void = {}) {
        self.onOpenTreemap = onOpenTreemap
    }

    var body: some View {
        ZStack {
            // Fundo temático (Classic = transparente; neon = gradiente escuro)
            themeManager.palette.backgroundView

            VStack(spacing: 0) {
                // FIXED HEADER SECTION
                VStack(spacing: 16) {
                    // Header Title & Buttons
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("MAC-LIMPO")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(themeManager.palette.accentGradient)
                                .shadow(
                                    color: themeManager.palette.glow
                                        ? themeManager.palette.glowColor.opacity(0.7) : .clear,
                                    radius: themeManager.palette.glow ? 8 : 0
                                )

                            Text("System Cleaner")
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.palette.secondaryText)
                        }

                        Spacer()

                        Button(action: {
                            onOpenTreemap()
                        }) {
                            Image(systemName: "square.grid.3x3.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(themeManager.palette.accentGradient)
                        }
                        .buttonStyle(.plain)
                        .help("Disk Map")

                        Button(action: {
                            viewModel.refreshDiskStats()
                            viewModel.scanAllCategories()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(themeManager.palette.accentGradient)
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

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(themeManager.palette.secondaryText)

                        TextField("Search cleaning categories", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(themeManager.palette.primaryText)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(themeManager.palette.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .help("Clear search")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .themedSurface(themeManager.palette, cornerRadius: 12)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 10)

                // SCROLLABLE LIST SECTION
                ScrollView {
                    VStack(spacing: 20) {
                        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

                        AppleIntelligenceInsightView(
                            insight: intelligenceInsight,
                            status: intelligenceStatus,
                            isGenerating: isGeneratingInsight,
                            generateInsight: generateStorageInsight
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                        // Cleaning Categories (apenas as implementadas)
                        // Cleaning Categories by Group
                        VStack(spacing: 20) {
                            ForEach(CleaningGroup.allCases) { group in
                                let categoriesInGroup = viewModel.services.keys
                                    .filter {
                                        guard $0.group == group else { return false }
                                        guard !query.isEmpty else { return true }
                                        return $0.rawValue.localizedCaseInsensitiveContains(query)
                                            || $0.description.localizedCaseInsensitiveContains(query)
                                    }
                                    .sorted { $0.rawValue < $1.rawValue }

                                if !categoriesInGroup.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        // Group Header
                                        HStack {
                                            Image(systemName: group.icon)
                                                .font(.system(size: 14))
                                                .foregroundColor(themeManager.palette.secondaryText)
                                            Text(group.rawValue)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(themeManager.palette.secondaryText)

                                            Text("\(categoriesInGroup.count)")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundColor(themeManager.palette.secondaryText)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(
                                                    Capsule()
                                                        .fill(themeManager.palette.secondaryText.opacity(0.12))
                                                )
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
                                                    isCleaning: viewModel.cleaningCategories.contains(category),
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

                        if !query.isEmpty && !viewModel.services.keys.contains(where: {
                            $0.rawValue.localizedCaseInsensitiveContains(query)
                                || $0.description.localizedCaseInsensitiveContains(query)
                        }) {
                            VStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(themeManager.palette.secondaryText)
                                Text("No categories found")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(themeManager.palette.primaryText)
                                Text("Try another search term")
                                    .font(.system(size: 12))
                                    .foregroundColor(themeManager.palette.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                        }

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
                            .background(themeManager.palette.accentGradient)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(
                                color: themeManager.palette.glow
                                    ? themeManager.palette.glowColor.opacity(0.6) : .clear,
                                radius: themeManager.palette.glow ? 14 : 0
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)

                        // Settings
                        VStack(spacing: 12) {
                            // Theme picker
                            ThemePickerView(themeManager: themeManager)

                            Toggle(isOn: $launchAtLoginService.isEnabled) {
                                Text("Launch at Login")
                                    .font(.system(size: 14))
                                    .foregroundColor(themeManager.palette.primaryText)
                            }
                            .toggleStyle(.switch)
                            .padding(.horizontal, 20)

                            Toggle(isOn: $cleaningOptions.aggressiveMode) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Aggressive cleaning")
                                        .font(.system(size: 14))
                                        .foregroundColor(themeManager.palette.primaryText)
                                    Text(
                                        "Also clears large regenerable caches (Chrome AI models, all unused Docker images)"
                                    )
                                    .font(.system(size: 11))
                                    .foregroundColor(themeManager.palette.secondaryText)
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
                        .foregroundColor(themeManager.palette.secondaryText)
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

            // Confirmation Overlay (inline — não fecha o popover)
            if let request = viewModel.confirmationRequest {
                CleaningConfirmationView(
                    request: request,
                    onConfirm: { dontAskAgain in
                        viewModel.confirmPendingClean(dontAskAgain: dontAskAgain)
                    },
                    onCancel: {
                        viewModel.cancelPendingClean()
                    }
                )
            }
        }
        .frame(width: 420, height: 700)
        .fontDesign(themeManager.palette.fontDesign)
        .animation(.easeInOut(duration: 0.35), value: themeManager.theme)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showProgress)
        .animation(.easeInOut(duration: 0.2), value: viewModel.confirmationRequest?.id)
        .onChange(of: cleaningOptions.aggressiveMode) { _, _ in
            // As estimativas mudam com o modo agressivo; re-escaneia para refletir.
            viewModel.scanAllCategories()
        }
    }

    private func generateStorageInsight() {
        guard !isGeneratingInsight else { return }
        isGeneratingInsight = true

        let results = Array(viewModel.scanResults.values)
        let total = viewModel.totalDiskSpace
        let used = viewModel.usedDiskSpace

        Task {
            let service = AppleIntelligenceService.shared
            let availability = await service.availability()

            do {
                let insight = try await service.generateStorageInsight(
                    scanResults: results,
                    totalDiskSpace: total,
                    usedDiskSpace: used
                )
                await MainActor.run {
                    intelligenceStatus = availability
                    intelligenceInsight = insight
                    isGeneratingInsight = false
                }
            } catch {
                await MainActor.run {
                    intelligenceStatus = availability
                    intelligenceInsight = error.localizedDescription
                    isGeneratingInsight = false
                }
            }
        }
    }
}
