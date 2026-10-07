// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import AppKit
import Foundation
@preconcurrency import UserNotifications

/// O que `docs/updates.json` anuncia: a versão mais nova publicada e as
/// novidades em inglês e português. O arquivo é escrito à mão a cada release
/// (skill `release`) e servido pelo raw.githubusercontent.com e pelo GitHub
/// Pages — nada de GitHub Actions nem de assinatura da Apple.
struct UpdateManifest: Codable, Equatable {
    struct Notes: Codable, Equatable {
        let title: String
        let changes: [String]
        let why: String?
    }

    let version: String
    let date: String?
    let important: Bool?
    let url: String?
    let notes: [String: Notes]

    /// Novidades no idioma em que o app está rodando (en ou pt-BR), com o
    /// inglês como reserva.
    func localizedNotes(language: String = Bundle.main.preferredLocalizations.first ?? "en") -> Notes? {
        notes[language] ?? notes[String(language.prefix(2))] ?? notes["en"] ?? notes.values.first
    }
}

/// Atualiza como o VintageLightbox: confere ao abrir e de hora em hora, fica em
/// silêncio quando não há nada (ou quando a rede falha), e só a verificação
/// manual responde "em dia" ou "não consegui verificar". Ao achar uma versão
/// nova, quem tem o Swift já começa a compilá-la em segundo plano — sem clique,
/// sem fechar o app: o install.sh troca o bundle no disco e a faixa oferece
/// "Reabrir Agora" (senão, a versão nova entra na próxima abertura). Uma falha
/// não é retentada sozinha por 24 h, e uma trava impede dois instaladores.
/// Sem ferramentas de compilação (instalou pelo .pkg), a faixa aponta para o
/// download. O ícone da barra ganha um ponto e sai uma notificação do macOS
/// por versão.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// Ordem de consulta. Só se acrescenta: apps já instalados só conhecem os
    /// endereços com que foram compilados.
    nonisolated static let manifestURLs = [
        URL(string: "https://raw.githubusercontent.com/alexkads/MAC-LIMPO/main/docs/updates.json")!,
        URL(string: "https://alexkads.github.io/MAC-LIMPO/updates.json")!,
    ]
    nonisolated static let installScriptURL = URL(string: "https://alexkads.github.io/MAC-LIMPO/install.sh")!
    nonisolated static let releasesURL = URL(string: "https://github.com/alexkads/MAC-LIMPO/releases/latest")!
    private static let notifiedKey = "notifiedUpdateVersion"
    private nonisolated static let failureKey = "updateFailure"
    /// Uma versão que falhou não é retentada sozinha antes disto.
    private nonisolated static let retryAfter: TimeInterval = 24 * 60 * 60
    /// Trava de um instalador em andamento; vence depois disto (build travado).
    private nonisolated static let lockLifetime: TimeInterval = 3 * 60 * 60
    private static let checkInterval: TimeInterval = 60 * 60

    enum State: Equatable {
        case idle
        case checking(manual: Bool)
        case available(UpdateManifest)
        /// Compilando em segundo plano; `step` é a última etapa do install.sh.
        case installing(UpdateManifest, step: String)
        case failed(UpdateManifest, reason: String, log: URL?)
        /// Instalada no disco; entra na próxima abertura ou em "Reabrir Agora".
        case installed(UpdateManifest)
        case upToDate(version: String)
        case unreachable(reason: String)
    }

    @Published private(set) var state: State = .idle {
        didSet {
            if state != oldValue { logger.log("Atualização: \(state)", level: .info) }
        }
    }
    /// "Depois": some até a próxima abertura do app (não é salvo), e uma
    /// versão ainda mais nova volta a aparecer.
    @Published private(set) var dismissedVersion: String?

    /// Versão deste app, do Info.plist. `nil` no `swift run` (sem bundle): aí
    /// não há o que atualizar e nada é consultado.
    nonisolated static let currentVersion: String? = {
        guard let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !short.contains("$(") else { return nil }
        return short
    }()

    private var timer: Timer?
    private var installPoll: Timer?

    /// Há algo para mostrar no ícone da barra de menus.
    var hasPendingUpdate: Bool {
        switch state {
        case let .available(manifest), let .installed(manifest): manifest.version != dismissedVersion
        case .installing, .failed: true
        default: false
        }
    }

    /// Começa as verificações automáticas: logo depois de abrir e de hora em hora.
    func start() {
        guard Self.currentVersion != nil, timer == nil else { return }
        // Um instalador ainda rodando (o app foi reaberto no meio do build):
        // volta a acompanhá-lo em vez de começar outro.
        if Self.installerIsRunning(), let manifest = Self.runningInstallManifest() {
            state = .installing(manifest, step: String(localized: "building"))
            watch(Self.installerRun, manifest: manifest)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.check(manual: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { _ in
            MainActor.assumeIsolated { UpdateChecker.shared.check(manual: false) }
        }
    }

    func check(manual: Bool) {
        switch state {
        case .installing, .checking: return
        case .installed where !manual: return
        default: break
        }
        // Já avisado e não dispensado: a checagem de hora em hora não precisa repetir.
        if !manual, case let .available(manifest) = state, manifest.version != dismissedVersion { return }
        guard let current = Self.currentVersion else {
            if manual { state = .unreachable(reason: String(localized: "This build has no version number (development build).")) }
            return
        }
        if manual { dismissedVersion = nil }
        let previous = state
        state = .checking(manual: manual)
        Task {
            let result = await Self.fetchManifest()
            switch result {
            case let .success(manifest) where Self.isVersion(manifest.version, newerThan: current):
                state = .available(manifest)
                if Self.canBuildFromSource, manual || !Self.failedRecently(manifest.version) {
                    install()
                } else if !manual {
                    notifyOnce(manifest, installed: false)
                }
            case .success:
                state = manual ? .upToDate(version: current) : .idle
            case let .failure(error):
                state = manual ? .unreachable(reason: error.localizedDescription) : Self.quiet(previous)
            }
        }
    }

    /// Volta ao que estava antes de uma checagem automática que falhou.
    private static func quiet(_ previous: State) -> State {
        if case .checking = previous { return .idle }
        return previous
    }

    func dismiss() {
        switch state {
        case let .available(manifest), let .failed(manifest, _, _):
            dismissedVersion = manifest.version
            state = .available(manifest)
        case let .installed(manifest):
            dismissedVersion = manifest.version
        case .upToDate, .unreachable:
            state = .idle
        default:
            break
        }
    }

    // MARK: - Consulta

    enum CheckError: LocalizedError {
        case noAnswer
        var errorDescription: String? {
            String(localized: "No update server answered. Check your internet connection.")
        }
    }

    nonisolated static func fetchManifest() async -> Result<UpdateManifest, Error> {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        // Desenvolvimento: MACLIMPO_UPDATE_URL=<url ou file://> troca os endereços.
        let urls = ProcessInfo.processInfo.environment["MACLIMPO_UPDATE_URL"].flatMap(URL.init(string:)).map { [$0] } ?? manifestURLs
        for url in urls {
            do {
                let (data, response) = try await session.data(for: freshRequest(url))
                if let http = response as? HTTPURLResponse, http.statusCode != 200 { continue }
                let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
                // Um arquivo sem versão válida ou sem título não vira aviso em branco.
                guard parse(manifest.version) != nil, manifest.localizedNotes()?.title.isEmpty == false else { continue }
                return .success(manifest)
            } catch {
                logger.log("Atualização: \(url.host() ?? "?") falhou — \(error.localizedDescription)", level: .warning)
            }
        }
        return .failure(CheckError.noAnswer)
    }

    /// Pede a cópia mais nova: o raw.githubusercontent guarda o arquivo por 5 min
    /// e o Pages por 10 — sem isto, logo depois de uma release o app ainda
    /// recebia a versão anterior e dizia "você está em dia". O parâmetro muda a
    /// chave do cache da CDN; o cabeçalho pede revalidação a quem o respeita.
    nonisolated static func freshRequest(_ url: URL, now: Date = Date()) -> URLRequest {
        var request = URLRequest(url: url)
        if url.scheme == "https", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "t", value: String(Int(now.timeIntervalSince1970)))]
            request.url = components.url ?? url
        }
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

    /// "v1.3.10" → [1, 3, 10]. Qualquer parte não numérica invalida a versão.
    nonisolated static func parse(_ version: String) -> [Int]? {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        return parts.compactMap(\.self)
    }

    /// Compara número a número (1.3.10 > 1.3.9); partes ausentes valem 0. Uma
    /// versão que não dá para ler nunca é "mais nova".
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        guard let new = parse(candidate), let old = parse(current) else { return false }
        for index in 0 ..< max(new.count, old.count) {
            let lhs = index < new.count ? new[index] : 0
            let rhs = index < old.count ? old[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    // MARK: - Notificação do macOS

    /// Uma notificação por versão e por momento: "disponível" (quando não dá
    /// para instalar sozinho) ou "instalada".
    private func notifyOnce(_ manifest: UpdateManifest, installed: Bool) {
        let defaults = UserDefaults.standard
        let tag = "\(installed ? "installed" : "available"):\(manifest.version)"
        guard defaults.string(forKey: Self.notifiedKey) != tag else { return }
        // Só um .app de verdade tem notificações (o swift run não tem bundle).
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        defaults.set(tag, forKey: Self.notifiedKey)
        let center = UNUserNotificationCenter.current()
        let title = installed
            ? String(localized: "MAC-LIMPO \(manifest.version) installed")
            : String(localized: "MAC-LIMPO \(manifest.version) is available")
        let body = installed
            ? String(localized: "It takes effect the next time MAC-LIMPO opens — or reopen it now from the menu bar.")
            : manifest.localizedNotes()?.title ?? ""
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "update-\(tag)", content: content, trigger: nil))
        }
    }

    // MARK: - Instalação

    /// Quem tem o Swift (Xcode ou Command Line Tools) atualiza como instalou:
    /// o install.sh compila a versão nova neste Mac, sem quarentena. Sem
    /// ferramentas de compilação (instalou pelo .pkg), abre a página da versão.
    nonisolated static let canBuildFromSource: Bool = {
        // Só olha arquivos — nada de Process aqui: esperar um processo roda o
        // run loop da thread principal, o SwiftUI redesenha a faixa no meio, a
        // faixa lê esta mesma constante ainda sendo inicializada e o app cai
        // (dispatch_once recursivo). Nem xcrun, que abre o diálogo "instalar
        // ferramentas". A pasta ativa é a do DEVELOPER_DIR, a escolhida com
        // xcode-select -s (/var/db/xcode_select_link) ou as padrão.
        let fm = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
            try? fm.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"),
            "/Applications/Xcode.app/Contents/Developer",
            "/Library/Developer/CommandLineTools",
        ].compactMap(\.self)
        return candidates.contains { developerDir in
            fm.isExecutableFile(atPath: "\(developerDir)/usr/bin/swift")
                || fm.isExecutableFile(atPath: "\(developerDir)/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift")
        }
    }()

    func install() {
        let manifest: UpdateManifest
        switch state {
        case let .available(found), let .failed(found, _, _): manifest = found
        default: return
        }
        guard Self.canBuildFromSource else {
            NSWorkspace.shared.open(manifest.url.flatMap(URL.init(string:)) ?? Self.releasesURL)
            return
        }
        if Self.installerIsRunning() {
            state = .installing(manifest, step: String(localized: "building"))
            watch(Self.installerRun, manifest: manifest)
            return
        }
        state = .installing(manifest, step: String(localized: "Downloading the installer…"))
        Task {
            do {
                try await Self.launchInstaller(for: manifest)
                watch(Self.installerRun, manifest: manifest)
            } catch {
                Self.releaseLock()
                Self.recordFailure(manifest.version)
                state = .failed(manifest, reason: error.localizedDescription, log: nil)
            }
        }
    }

    /// Reabre na versão instalada: sai primeiro (a checagem de instância única
    /// da versão nova fecharia a si mesma se esta ainda estivesse aberta).
    func reopenNow() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #"( sleep 1; /usr/bin/open "$0" --args --updated ) > /dev/null 2>&1 &"#,
                             Bundle.main.bundleURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    struct InstallerRun {
        let log: URL
        let status: URL
    }

    nonisolated static let updateFolder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MAC-LIMPO-build/update", isDirectory: true)
    nonisolated static let installerRun = InstallerRun(
        log: updateFolder.appendingPathComponent("install.log"),
        status: updateFolder.appendingPathComponent("install.status")
    )
    private nonisolated static let lockFile = updateFolder.appendingPathComponent("install.lock")

    /// Há um instalador nosso em andamento (trava recente e sem status final).
    nonisolated static func installerIsRunning() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: lockFile.path),
              let created = attributes[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(created) < lockLifetime
            && !FileManager.default.fileExists(atPath: installerRun.status.path)
    }

    /// A versão que o instalador em andamento está instalando (gravada na trava).
    nonisolated static func runningInstallManifest() -> UpdateManifest? {
        guard let data = try? Data(contentsOf: lockFile) else { return nil }
        return try? JSONDecoder().decode(UpdateManifest.self, from: data)
    }

    nonisolated static func releaseLock() {
        try? FileManager.default.removeItem(at: lockFile)
    }

    nonisolated static func failedRecently(_ version: String, now: Date = Date()) -> Bool {
        guard let failure = UserDefaults.standard.dictionary(forKey: failureKey),
              failure["version"] as? String == version,
              let when = failure["date"] as? Double else { return false }
        return now.timeIntervalSince1970 - when < retryAfter
    }

    nonisolated static func recordFailure(_ version: String) {
        UserDefaults.standard.set(["version": version, "date": Date().timeIntervalSince1970], forKey: failureKey)
    }

    enum InstallError: LocalizedError {
        case incompleteScript
        var errorDescription: String? {
            String(localized: "The installer download was incomplete. Try again.")
        }
    }

    /// Baixa o install.sh para um arquivo (nunca `curl | sh`), confere que veio
    /// inteiro e o roda desanexado e com prioridade baixa (`nice`), no modo
    /// `--in-background`: compila e troca o bundle no disco sem fechar o app.
    nonisolated static func launchInstaller(for manifest: UpdateManifest) async throws {
        try FileManager.default.createDirectory(at: updateFolder, withIntermediateDirectories: true)
        let script = updateFolder.appendingPathComponent("install.sh")
        try? FileManager.default.removeItem(at: installerRun.status)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        // Desenvolvimento: MACLIMPO_UPDATE_INSTALLER=<url ou file://> troca o script.
        let source = ProcessInfo.processInfo.environment["MACLIMPO_UPDATE_INSTALLER"].flatMap(URL.init(string:)) ?? installScriptURL
        let (data, response) = try await URLSession(configuration: configuration).data(from: source)
        let text = String(decoding: data, as: UTF8.self)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw InstallError.incompleteScript }
        guard text.hasPrefix("#!/bin/sh"), text.contains("--in-background)"), text.contains("Docs:") else {
            throw InstallError.incompleteScript
        }
        try data.write(to: script)
        // A trava guarda a versão: se o app for reaberto no meio, retoma daqui.
        try JSONEncoder().encode(manifest).write(to: lockFile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Subshell em segundo plano: o sh de fora sai na hora e o instalador
        // fica com o launchd. --dest: reinstala onde este app está.
        let destination = Bundle.main.bundleURL.deletingLastPathComponent().path
        process.arguments = [
            "-c", #"( /usr/bin/nice -n 10 /bin/sh "$0" --in-background --dest "$3" > "$1" 2>&1; echo $? > "$2" ) &"#,
            script.path, installerRun.log.path, installerRun.status.path, destination,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        process.environment = environment
        try process.run()
    }

    /// Acompanha o log ("▸ etapa") até o instalador terminar; no fim confere
    /// a versão que ficou no disco.
    private func watch(_ run: InstallerRun, manifest: UpdateManifest) {
        installPoll?.invalidate()
        // O timer roda no run loop principal, então já está no MainActor.
        installPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { UpdateChecker.shared.poll(run, manifest: manifest) }
        }
    }

    private func poll(_ run: InstallerRun, manifest: UpdateManifest) {
        let log = (try? String(contentsOf: run.log, encoding: .utf8)) ?? ""
        if let statusText = try? String(contentsOf: run.status, encoding: .utf8) {
            installPoll?.invalidate()
            installPoll = nil
            Self.releaseLock()
            let code = Int(statusText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
            if code != 0 {
                Self.recordFailure(manifest.version)
                state = .failed(manifest, reason: Self.failureReason(in: log), log: run.log)
            } else if let installed = Self.installedVersion(), !Self.isVersion(manifest.version, newerThan: installed) {
                state = .installed(manifest)
                notifyOnce(manifest, installed: true)
            } else {
                Self.recordFailure(manifest.version)
                state = .failed(manifest, reason: String(localized: "The new version wasn't found after installing."), log: run.log)
            }
            return
        }
        if let step = Self.lastStep(in: log) {
            state = .installing(manifest, step: step)
        }
    }

    /// Versão do bundle no disco agora (o install.sh troca o deste app). Lido
    /// do arquivo, não do `Bundle`, que guarda o Info.plist de quando abriu.
    nonisolated static func installedVersion() -> String? {
        let plist = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
        return (NSDictionary(contentsOf: plist) as? [String: Any])?["CFBundleShortVersionString"] as? String
    }

    /// Última linha "▸ etapa" do install.sh, sem as cores do terminal.
    nonisolated static func lastStep(in log: String) -> String? {
        log.split(separator: "\n").reversed()
            .map { $0.replacingOccurrences(of: #"\x1b\[[0-9;]*m"#, with: "", options: .regularExpression) }
            .first { $0.hasPrefix("▸ ") }
            .map { String($0.dropFirst(2)) }
    }

    /// Primeira linha "✗ motivo" do install.sh.
    nonisolated static func failureReason(in log: String) -> String {
        log.split(separator: "\n")
            .map { $0.replacingOccurrences(of: #"\x1b\[[0-9;]*m"#, with: "", options: .regularExpression) }
            .first { $0.hasPrefix("✗ ") }
            .map { String($0.dropFirst(2)) }
            ?? String(localized: "The installer stopped with an error.")
    }
}
