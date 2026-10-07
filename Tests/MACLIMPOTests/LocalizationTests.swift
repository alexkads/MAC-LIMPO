import Foundation
import XCTest

/// O app é inglês (base) e português do Brasil. Estes testes guardam o catálogo
/// gerado por `make strings`: todo texto da interface precisa de tradução, e a
/// tradução precisa dos mesmos marcadores (%@, %lld…) — um marcador trocado
/// derruba o app na hora de formatar.
final class LocalizationTests: XCTestCase {
    private static let localizationDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // MACLIMPOTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // raiz
        .appendingPathComponent("Localization")

    private struct Entry {
        let key: String
        let source: String
        let portuguese: String?
    }

    private func entries(in catalog: String) throws -> [Entry] {
        let url = Self.localizationDir.appendingPathComponent(catalog)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        return strings.compactMap { key, entry in
            // Chaves que saíram do código ficam "stale" até o próximo make strings.
            if entry["extractionState"] as? String == "stale" { return nil }
            if entry["shouldTranslate"] as? Bool == false { return nil }
            if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            let localizations = entry["localizations"] as? [String: Any]
            func value(_ language: String) -> String? {
                let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                return unit?["value"] as? String
            }
            return Entry(key: key, source: value("en") ?? key, portuguese: value("pt-BR"))
        }
    }

    /// Os marcadores de formato, sem a posição (%1$@ e %@ valem o mesmo tipo).
    private func placeholders(_ text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:lld|ld|lu|llu|d|u|f|@|%)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            let token = String(text[Range(match.range, in: text)!])
            return token.replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression)
        }
        .filter { $0 != "%%" }
        .sorted()
    }

    func testEveryStringHasPortuguese() throws {
        for catalog in ["Localizable.xcstrings", "InfoPlist.xcstrings"] {
            let missing = try entries(in: catalog).filter { ($0.portuguese ?? "").isEmpty }.map(\.key)
            XCTAssertEqual(missing, [], "\(catalog): sem tradução pt-BR — rode make strings e traduza")
        }
    }

    func testTranslationsKeepPlaceholders() throws {
        for entry in try entries(in: "Localizable.xcstrings") {
            guard let portuguese = entry.portuguese else { continue }
            XCTAssertEqual(placeholders(portuguese), placeholders(entry.source), "marcadores diferentes em \(entry.key.debugDescription)")
        }
    }
}
