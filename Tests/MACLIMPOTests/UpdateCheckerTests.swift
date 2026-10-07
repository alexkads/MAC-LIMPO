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
