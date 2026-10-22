import Foundation
import XCTest
@testable import MAC_LIMPO

/// Aviso de versão nova: comparação de versões, leitura do docs/updates.json
/// publicado e as linhas do install.sh que viram etapa/motivo na faixa.
final class UpdateCheckerTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testVersionComparisonIsNumeric() {
        XCTAssertTrue(UpdateChecker.isVersion("1.3.10", newerThan: "1.3.9"))
        XCTAssertTrue(UpdateChecker.isVersion("v1.4", newerThan: "1.3.24"))
        XCTAssertTrue(UpdateChecker.isVersion("2.0.0", newerThan: "1.99.99"))
        XCTAssertFalse(UpdateChecker.isVersion("1.3.9", newerThan: "1.3.10"))
        XCTAssertFalse(UpdateChecker.isVersion("1.3", newerThan: "1.3.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.3.24", newerThan: "1.3.24"))
    }

    func testUnreadableVersionIsNeverNewer() {
        XCTAssertFalse(UpdateChecker.isVersion("1.4.0-beta", newerThan: "1.3.0"))
        XCTAssertFalse(UpdateChecker.isVersion("", newerThan: "1.3.0"))
        XCTAssertFalse(UpdateChecker.isVersion("abc", newerThan: "1.3.0"))
        XCTAssertNil(UpdateChecker.parse("1..2"))
    }

    /// O docs/updates.json publicado precisa anunciar exatamente a versão do
    /// VERSION — senão o app avisaria de uma versão que a release não tem.
    func testPublishedManifestMatchesVersionFile() throws {
        let version = try String(contentsOf: Self.root.appendingPathComponent("VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try Data(contentsOf: Self.root.appendingPathComponent("docs/updates.json"))
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
        XCTAssertEqual(manifest.version, version, "docs/updates.json e VERSION precisam andar juntos (skill release)")
        for language in ["en", "pt-BR"] {
            let notes = try XCTUnwrap(manifest.notes[language], "faltam as novidades em \(language)")
            XCTAssertFalse(notes.title.isEmpty)
            XCTAssertFalse(notes.changes.isEmpty)
        }
        XCTAssertEqual(manifest.url, "https://github.com/alexkads/MAC-LIMPO/releases/tag/v\(version)")
    }

    func testNotesFollowTheAppLanguage() throws {
        let json = #"{"version":"9.9.9","notes":{"en":{"title":"Hello","changes":[]},"pt-BR":{"title":"Olá","changes":[]}}}"#
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.localizedNotes(language: "pt-BR")?.title, "Olá")
        XCTAssertEqual(manifest.localizedNotes(language: "en")?.title, "Hello")
        XCTAssertEqual(manifest.localizedNotes(language: "fr")?.title, "Hello")
    }

    func testInstallerLogLines() {
        let log = "\u{1b}[1;36m▸ checking this Mac\u{1b}[0m\n✓ macOS 27.0\n\n\u{1b}[1;36m▸ building (2–5 minutes the first time)\u{1b}[0m\n"
        XCTAssertEqual(UpdateChecker.lastStep(in: log), "building (2–5 minutes the first time)")
        XCTAssertEqual(UpdateChecker.failureReason(in: log + "\u{1b}[1;31m✗ the build failed.\u{1b}[0m\n"), "the build failed.")
    }

    /// O botão Atualizar roda o install.sh com --from-app; o script precisa conhecê-lo.
    func testInstallScriptKnowsFromApp() throws {
        let script = try String(contentsOf: Self.root.appendingPathComponent("docs/install.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("--from-app)"))
        XCTAssertTrue(script.contains("--updated"))
    }
}

/// Atualização automática: uma versão que falhou espera 24 h antes de ser
/// tentada sozinha de novo; outra versão não é afetada.
final class UpdateRetryTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "updateFailure")
        super.tearDown()
    }

    func testFailedVersionWaitsADay() {
        UpdateChecker.recordFailure("9.9.9")
        XCTAssertTrue(UpdateChecker.failedRecently("9.9.9"))
        XCTAssertFalse(UpdateChecker.failedRecently("9.9.10"))
        XCTAssertFalse(UpdateChecker.failedRecently("9.9.9", now: Date().addingTimeInterval(25 * 60 * 60)))
    }

    func testInstallScriptKnowsInBackground() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("docs/install.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("--in-background)"))
        XCTAssertTrue(script.contains(#"[ "$IN_BACKGROUND" -eq 1 ] || quit_running_app"#))
    }
}

/// "Procurar Atualizações" depois de uma instalação em segundo plano: a versão
/// já está no disco, só falta reabrir — nada de recompilar.
final class UpdateOutcomeTests: XCTestCase {
    func testComparesWithTheVersionOnDisk() {
        XCTAssertEqual(UpdateChecker.outcome(announced: "1.3.29", running: "1.3.28", onDisk: "1.3.28"), .available)
        XCTAssertEqual(UpdateChecker.outcome(announced: "1.3.29", running: "1.3.28", onDisk: "1.3.29"), .installedPendingReopen)
        XCTAssertEqual(UpdateChecker.outcome(announced: "1.3.29", running: "1.3.28", onDisk: nil), .available)
        XCTAssertEqual(UpdateChecker.outcome(announced: "1.3.28", running: "1.3.28", onDisk: "1.3.28"), .upToDate)
    }
}

/// A atualização em segundo plano não pede senha: só roda onde dá para trocar
/// o bundle sem ela. A cópia do .pkg é do root.
final class UpdateInPlaceTests: XCTestCase {
    private var apps: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        apps = fm.temporaryDirectory.appendingPathComponent("maclimpo-apps-\(UUID().uuidString)")
        try fm.createDirectory(at: apps.appendingPathComponent("MAC-LIMPO.app/Contents"), withIntermediateDirectories: true)
        try Data("<plist/>".utf8).write(to: apps.appendingPathComponent("MAC-LIMPO.app/Contents/Info.plist"))
    }

    override func tearDownWithError() throws {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: apps.path)
        try? fm.removeItem(at: apps)
    }

    func testOwnBundleInWritableFolderIsReplaceable() {
        XCTAssertTrue(UpdateChecker.isReplaceable(bundle: apps.appendingPathComponent("MAC-LIMPO.app")))
    }

    func testBundleOfAnotherUserIsNot() {
        XCTAssertFalse(UpdateChecker.isReplaceable(bundle: apps.appendingPathComponent("MAC-LIMPO.app"), user: getuid() &+ 1))
    }

    func testReadOnlyFolderIsNot() throws {
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: apps.path)
        XCTAssertFalse(UpdateChecker.isReplaceable(bundle: apps.appendingPathComponent("MAC-LIMPO.app")))
    }
}

/// Trava do instalador: só conta como "instalando" com o processo vivo. Um
/// logout ou reinício mata o instalador sem deixar status.
final class InstallerLockTests: XCTestCase {
    private var folder: URL!
    private let fm = FileManager.default
    private var shell: Process?

    private var lock: URL { folder.appendingPathComponent("install.lock") }
    private var status: URL { folder.appendingPathComponent("install.status") }
    private var pid: URL { folder.appendingPathComponent("install.pid") }

    override func setUpWithError() throws {
        folder = fm.temporaryDirectory.appendingPathComponent("maclimpo-lock-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: lock)
    }

    override func tearDownWithError() throws {
        shell?.terminate()
        try? fm.removeItem(at: folder)
    }

    /// Um sh vivo, como o subshell que roda o install.sh, e o PID dele no arquivo.
    private func startShell() throws -> pid_t {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 30; true"]
        try process.run()
        shell = process
        try "\(process.processIdentifier)\n".write(to: pid, atomically: true, encoding: .utf8)
        return process.processIdentifier
    }

    private func running(now: Date = Date()) -> Bool {
        UpdateChecker.installerIsRunning(lock: lock, status: status, pid: pid, now: now)
    }

    func testLiveInstallerIsRunning() throws {
        _ = try startShell()
        XCTAssertTrue(running())
    }

    func testKilledInstallerIsNot() throws {
        _ = try startShell()
        shell?.terminate()
        shell?.waitUntilExit()
        XCTAssertFalse(running(), "logout ou reinício no meio do build")
    }

    func testLockWithoutProcessIsNot() {
        XCTAssertFalse(running(), "trava de uma versão antiga, sem install.pid")
    }

    func testFinishedOrExpiredIsNot() throws {
        _ = try startShell()
        XCTAssertFalse(running(now: Date().addingTimeInterval(4 * 60 * 60)), "trava vencida")
        try Data("0\n".utf8).write(to: status)
        XCTAssertFalse(running(), "status gravado = terminou")
    }

    /// Depois de um reinício o mesmo PID pode ser de outro processo, que
    /// começou depois de o arquivo ser gravado.
    func testReusedPIDIsNotTheInstaller() throws {
        _ = try startShell()
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: pid.path)
        XCTAssertFalse(UpdateChecker.installerProcessIsAlive(pidFile: pid))
    }
}

/// O install.sh publicado é o que os apps instalados rodam para se atualizar.
final class InstallScriptSafetyTests: XCTestCase {
    private let script: String = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent("docs/install.sh"), encoding: .utf8)) ?? ""
    }()

    /// Sem a API do GitHub, compilava a `main` em silêncio.
    func testNeverFallsBackToMain() {
        XCTAssertFalse(script.contains(#"REF="main""#))
        XCTAssertTrue(script.contains("releases/latest"))
    }

    /// Copia ao lado e troca por renomeação: uma cópia que falha não apaga o app.
    func testSwapsAfterCopyingAside() throws {
        let copy = try XCTUnwrap(script.range(of: #"run ditto "$BUILT" "$STAGED""#))
        let swap = try XCTUnwrap(script.range(of: #"run mv "$STAGED" "$TARGET""#))
        XCTAssertLessThan(copy.lowerBound, swap.lowerBound)
    }

    /// Em segundo plano não há como pedir senha: para antes de compilar.
    func testBackgroundUpdateStopsEarlyWithoutPermission() throws {
        let check = try XCTUnwrap(script.range(of: #"[ "$IN_BACKGROUND" -eq 1 ] && ! can_remove"#))
        let build = try XCTUnwrap(script.range(of: "./Scripts/bundle-app.sh) >"))
        XCTAssertLessThan(check.lowerBound, build.lowerBound)
    }
}

/// Logo depois de uma release a CDN ainda guarda o manifesto anterior; o
/// pedido do app precisa furar esse cache.
final class UpdateFreshRequestTests: XCTestCase {
    func testManifestRequestBypassesCaches() {
        let url = URL(string: "https://raw.githubusercontent.com/alexkads/MAC-LIMPO/main/docs/updates.json")!
        let request = UpdateChecker.freshRequest(url, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(request.url?.absoluteString, url.absoluteString + "?t=1800000000")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
    }

    func testLocalFilesAreLeftAlone() {
        let url = URL(string: "file:///tmp/updates.json")!
        XCTAssertEqual(UpdateChecker.freshRequest(url).url, url)
    }
}
