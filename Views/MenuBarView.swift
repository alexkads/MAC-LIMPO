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
            scanningStatus[category] = String(localized: "Starting…")
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
                    category: category, estimatedSize: 0, itemCount: 0, items: [String(localized: "Scan timed out — refresh to retry")]
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
        // A limpeza total do Docker apaga bancos de dados: pergunta sempre.
        let dockerWipe = CleaningOptions.shared.dockerFullCleanup && categories.contains(.docker)
        if skipCleaningConfirmation, !dockerWipe {
            onConfirm()
            return
        }

        let totalSize = categories.reduce(Int64(0)) { $0 + (scanResults[$1]?.estimatedSize ?? 0) }
        let sizeText = FileSystemHelper.shared.formatBytes(totalSize)
        let title = categories.count == 1
            ? String(localized: "Clean \(categories[0].displayName)?")
            : String(localized: "Clean \(categories.count) categories?")
        var body = String(
            localized: "About \(sizeText) will be freed. Whenever possible, items go to the Trash and can be restored from there."
        )
        if CleaningOptions.shared.aggressiveMode {
            body += "\n\n" + String(
                localized: "⚡️ Aggressive mode is on: also removes large regenerable caches (Chrome AI models, unused Docker images)."
            )
        }
        if dockerWipe {
            body += "\n\n" + String(
                localized: "⚠️ Docker full cleanup is on: all containers are stopped and removed, along with ALL images and volumes — databases included. This doesn't go to the Trash."
            )
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
                currentOperation = String(localized: "Cleaning \(total) categories…")
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
                        currentOperation = String(localized: "Cleaning… \(done)/\(total) categories")
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

extension CleaningCategory {
    /// Busca do popover: casa o nome traduzido, a descrição traduzida e o
    /// rawValue (inglês), para que termos em inglês continuem funcionando.
    /// Consulta vazia casa tudo.
    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return displayName.localizedCaseInsensitiveContains(query)
            || description.localizedCaseInsensitiveContains(query)
            || rawValue.localizedCaseInsensitiveContains(query)
    }
}

extension Sequence<CleaningCategory> {
    /// Ordem de exibição: pelo nome traduzido, como o Finder ordena.
    func sortedForDisplay() -> [CleaningCategory] {
        sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

struct MenuBarView: View {
    /// "Version 1.3.9 (12)", do Info.plist gerado por `Scripts/bundle-app.sh`.
    /// `nil` no `swift run`, que roda o executável solto, sem bundle.
    static let appVersion: String? = {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String, !short.contains("$(") else { return nil }
        guard let build = info?["CFBundleVersion"] as? String, !build.contains("$(") else {
            return String(localized: "Version \(short)")
        }
        return String(localized: "Version \(short) (\(build))")
    }()

    @StateObject private var viewModel = MenuBarViewModel()
    @StateObject private var launchAtLoginService = LaunchAtLoginService()
    @ObservedObject private var cleaningOptions = CleaningOptions.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var searchText = ""
    @State private var intelligenceInsight: String?
    @State private var intelligenceStatus: AppleIntelligenceAvailability?
    @State private var isGeneratingInsight = false
    let onOpenDiskXRay: () -> Void

    init(onOpenDiskXRay: @escaping () -> Void = {}) {
        self.onOpenDiskXRay = onOpenDiskXRay
    }

    /// Ícone dos botões do cabeçalho: gradiente do tema, ou a cor do texto no
    /// Liquid Glass (o vidro já dá o destaque; gradiente sobre vidro conflita).
    @ViewBuilder
    private func headerIcon(_ name: String) -> some View {
        let image = Image(systemName: name).font(.system(size: 16, weight: .semibold))
        if themeManager.palette.isGlass {
            image.foregroundStyle(.primary)
        } else {
            image.foregroundStyle(themeManager.palette.accentGradient)
        }
    }

    var body: some View {
        ZStack {
            // Fundo temático (Classic = transparente; neon = gradiente escuro)
            themeManager.palette.backgroundView

            if themeManager.palette.isGlass {
                // Liquid Glass: tudo nativo (List, Gauge, Picker, NSSearchField, vidro).
                NativeMenuBarContent(
                    viewModel: viewModel,
                    launchAtLogin: launchAtLoginService,
                    cleaningOptions: cleaningOptions,
                    themeManager: themeManager,
                    searchText: $searchText,
                    insight: intelligenceInsight,
                    insightStatus: intelligenceStatus,
                    isGeneratingInsight: isGeneratingInsight,
                    generateInsight: generateStorageInsight,
                    onOpenDiskXRay: onOpenDiskXRay,
                    version: Self.appVersion
                )
            } else {
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

                            HStack(spacing: themeManager.palette.isGlass ? 6 : 12) {
                                Button(action: {
                                    onOpenDiskXRay()
                                }) {
                                    headerIcon("rays")
                                }
                                .themedSecondaryButton(themeManager.palette)
                                .help("Disk X-Ray")
                                .accessibilityLabel("Open Disk X-Ray")

                                Button(action: {
                                    viewModel.refreshDiskStats()
                                    viewModel.scanAllCategories()
                                }) {
                                    headerIcon("arrow.clockwise")
                                }
                                .themedSecondaryButton(themeManager.palette)
                                .help("Refresh scan")
                                .accessibilityLabel("Refresh scan")
                            }
                            .themedGlassGroup(themeManager.palette)
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
                        .themedControlSurface(themeManager.palette, cornerRadius: 12)
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
                                            return $0.matchesSearch(query)
                                        }
                                        .sortedForDisplay()

                                    if !categoriesInGroup.isEmpty {
                                        VStack(alignment: .leading, spacing: 12) {
                                            // Group Header
                                            HStack {
                                                Image(systemName: group.icon)
                                                    .font(.system(size: 14))
                                                    .foregroundColor(themeManager.palette.secondaryText)
                                                Text(group.title)
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

                            if !query.isEmpty && !viewModel.services.keys.contains(where: { $0.matchesSearch(query) }) {
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
                                if themeManager.palette.isGlass {
                                    // O estilo .glassProminent desenha fundo, forma e
                                    // estados (pressionado, desabilitado) sozinho.
                                    Label("Clean All", systemImage: "sparkles")
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                } else {
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
                            }
                            .themedProminentButton(themeManager.palette)
                            .controlSize(themeManager.palette.isGlass ? .large : .regular)
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

                                Toggle(isOn: $cleaningOptions.dockerFullCleanup) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Docker full cleanup")
                                            .font(.system(size: 14))
                                            .foregroundColor(themeManager.palette.primaryText)
                                        Text(
                                            "Stops all containers and deletes every container, image and volume — databases included"
                                        )
                                        .font(.system(size: 11))
                                        .foregroundColor(themeManager.palette.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .toggleStyle(.switch)
                                .padding(.horizontal, 20)
                            }

                            // Quit Button + versão
                            VStack(spacing: 4) {
                                Button("Quit MAC-LIMPO") {
                                    NSApplication.shared.terminate(nil)
                                }
                                .themedSecondaryButton(themeManager.palette)
                                .foregroundColor(themeManager.palette.secondaryText)
                                .font(.system(size: 12))

                                if let version = Self.appVersion {
                                    Text(version)
                                        .font(.system(size: 10))
                                        .foregroundColor(themeManager.palette.secondaryText.opacity(0.6))
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.bottom, 20)
                        }
                    }
                }

            }

            // Painéis inline (não fecham o popover): nativos no Liquid Glass.
            if viewModel.showProgress, let category = viewModel.currentCleaningCategory {
                if themeManager.palette.isGlass {
                    NativeProgressPanel(
                        category: category,
                        isShowing: $viewModel.showProgress,
                        progress: viewModel.cleaningProgress,
                        currentOperation: viewModel.currentOperation
                    )
                } else {
                    CleaningProgressView(
                        category: category,
                        isShowing: $viewModel.showProgress,
                        progress: viewModel.cleaningProgress,
                        currentOperation: viewModel.currentOperation
                    )
                }
            }

            if viewModel.showResults, let result = viewModel.lastResult {
                if themeManager.palette.isGlass {
                    NativeResultsPanel(result: result, isShowing: $viewModel.showResults)
                } else {
                    ResultsView(result: result, isShowing: $viewModel.showResults)
                }
            }

            if let request = viewModel.confirmationRequest {
                if themeManager.palette.isGlass {
                    NativeConfirmationPanel(
                        request: request,
                        onConfirm: { dontAskAgain in viewModel.confirmPendingClean(dontAskAgain: dontAskAgain) },
                        onCancel: { viewModel.cancelPendingClean() }
                    )
                } else {
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
        .onChange(of: cleaningOptions.dockerFullCleanup) { _, _ in
            viewModel.scanCategory(.docker)
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
