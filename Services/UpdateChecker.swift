// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import AppKit
import Foundation
@preconcurrency import UserNotifications

/// O que `docs/updates.json` anuncia: a versão mais nova publicada e as
/// novidades em inglês e português. O arquivo é escrito à mão a cada release
/// (skill `release`) e servido pelo raw.githubusercontent.com e pelo GitHub
/// Pages — nada de GitHub Actions nem de assinatura da Apple.
struct UpdateManifest: Decodable, Equatable {
    struct Notes: Decodable, Equatable {
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

/// Avisa quando há versão nova, como o VintageLightbox: confere ao abrir e de
/// hora em hora, fica em silêncio quando não há nada (ou quando a rede falha),
/// e só a verificação manual responde "em dia" ou "não consegui verificar".
/// Ao achar uma versão nova, o ícone da barra de menus ganha um ponto, o
/// popover mostra uma faixa (Atualizar · Novidades · Depois) e sai uma
/// notificação do macOS — uma vez por versão.
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
    private static let checkInterval: TimeInterval = 60 * 60

    enum State: Equatable {
        case idle
        case checking(manual: Bool)
        case available(UpdateManifest)
        /// Compilando em segundo plano; `step` é a última etapa do install.sh.
        case installing(UpdateManifest, step: String)
        case failed(UpdateManifest, reason: String, log: URL?)
        case upToDate(version: String)
        case unreachable(reason: String)
    }

    @Published private(set) var state: State = .idle
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
        case let .available(manifest): manifest.version != dismissedVersion
        case .installing, .failed: true
        default: false
        }
    }

    /// Começa as verificações automáticas: logo depois de abrir e de hora em hora.
    func start() {
        guard Self.currentVersion != nil, timer == nil else { return }
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
                if !manual { notifyOnce(manifest) }
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
                let (data, response) = try await session.data(from: url)
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

    private func notifyOnce(_ manifest: UpdateManifest) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.notifiedKey) != manifest.version else { return }
        // Só um .app de verdade tem notificações (o swift run não tem bundle).
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        defaults.set(manifest.version, forKey: Self.notifiedKey)
        let center = UNUserNotificationCenter.current()
        let title = String(localized: "MAC-LIMPO \(manifest.version) is available")
        let body = manifest.localizedNotes()?.title ?? ""
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "update-\(manifest.version)", content: content, trigger: nil))
        }
    }

    // MARK: - Instalação

    /// Quem tem o Swift (Xcode ou Command Line Tools) atualiza como instalou:
    /// o install.sh compila a versão nova neste Mac, sem quarentena. Sem
    /// ferramentas de compilação (instalou pelo .pkg), abre a página da versão.
    nonisolated static let canBuildFromSource: Bool = {
        // xcode-select -p não abre o diálogo "instalar ferramentas", ao contrário do xcrun.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        let developerDir = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, !developerDir.isEmpty else { return false }
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: "\(developerDir)/usr/bin/swift")
            || fm.isExecutableFile(atPath: "\(developerDir)/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift")
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
        state = .installing(manifest, step: String(localized: "Downloading the installer…"))
        Task {
            do {
                let run = try await Self.launchInstaller()
                watch(run, manifest: manifest)
            } catch {
                state = .failed(manifest, reason: error.localizedDescription, log: nil)
            }
        }
    }

    struct InstallerRun {
        let log: URL
        let status: URL
    }

    enum InstallError: LocalizedError {
        case incompleteScript
        var errorDescription: String? {
            String(localized: "The installer download was incomplete. Try again.")
        }
    }

    /// Baixa o install.sh para um arquivo (nunca `curl | sh`), confere que veio
    /// inteiro e o roda desanexado: ele continua mesmo quando fecha este app
    /// para trocar o bundle, e no fim reabre a versão nova com `--updated`.
    nonisolated static func launchInstaller() async throws -> InstallerRun {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MAC-LIMPO-build/update", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appendingPathComponent("install.sh")
        let log = folder.appendingPathComponent("install.log")
        let status = folder.appendingPathComponent("install.status")
        try? FileManager.default.removeItem(at: status)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let (data, response) = try await URLSession(configuration: configuration).data(from: installScriptURL)
        let text = String(decoding: data, as: UTF8.self)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              text.hasPrefix("#!/bin/sh"), text.contains("--from-app"), text.contains("Docs:") else {
            throw InstallError.incompleteScript
        }
        try data.write(to: script)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Subshell em segundo plano: o sh de fora sai na hora e o instalador
        // fica com o launchd — sobrevive ao fechamento deste app.
        // --dest: reinstala onde este app está (pode ser ~/Applications).
        let destination = Bundle.main.bundleURL.deletingLastPathComponent().path
        process.arguments = ["-c", #"( /bin/sh "$0" --from-app --dest "$3" > "$1" 2>&1; echo $? > "$2" ) &"#,
                             script.path, log.path, status.path, destination]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        return InstallerRun(log: log, status: status)
    }

    /// Acompanha o log ("▸ etapa") até o instalador fechar o app. Se ele
    /// terminar antes disso com erro, mostra o motivo e o caminho do log.
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
            let code = Int(statusText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
            if code != 0 {
                state = .failed(manifest, reason: Self.failureReason(in: log), log: run.log)
            }
            return
        }
        if let step = Self.lastStep(in: log) {
            state = .installing(manifest, step: step)
        }
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
