import XCTest
@testable import MAC_LIMPO

/// Testa as lógicas "manter só a versão mais nova" dos runtimes de simulador
/// e dos NDKs do Android.
final class RuntimeSelectionTests: XCTestCase {
    // MARK: - Simulator runtimes

    private struct RuntimeFixture {
        let id: String
        let runtime: String
        let version: String
        var size: Int64 = 1000
        var deletable = true
    }

    private func runtimeJSON(_ entries: [RuntimeFixture]) -> String {
        let body = entries.map { entry in
            """
            "\(entry.id)": {
                "runtimeIdentifier": "\(entry.runtime)",
                "version": "\(entry.version)",
                "sizeBytes": \(entry.size),
                "deletable": \(entry.deletable),
                "state": "Ready"
            }
            """
        }.joined(separator: ",")
        return "{\(body)}"
    }

    func testKeepsNewestRuntimePerPlatform() {
        let json = runtimeJSON([
            RuntimeFixture(
                id: "AAA",
                runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-3",
                version: "18.3.1",
                size: 8000
            ),
            RuntimeFixture(
                id: "BBB",
                runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                version: "26.5",
                size: 8500
            ),
            RuntimeFixture(id: "CCC", runtime: "com.apple.CoreSimulator.SimRuntime.watchOS-11-0", version: "11.0")
        ])
        let obsolete = IOSSimulatorsCleaningService.obsoleteRuntimes(fromJSON: json)
        XCTAssertEqual(obsolete.map(\.identifier), ["AAA"])
        XCTAssertEqual(obsolete.first?.platform, "iOS")
        XCTAssertEqual(obsolete.first?.sizeBytes, 8000)
    }

    func testNonDeletableRuntimeIsNeverReturned() {
        let json = runtimeJSON([
            RuntimeFixture(
                id: "AAA",
                runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-3",
                version: "18.3.1",
                deletable: false
            ),
            RuntimeFixture(id: "BBB", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5", version: "26.5")
        ])
        let obsolete = IOSSimulatorsCleaningService.obsoleteRuntimes(fromJSON: json)
        XCTAssertTrue(obsolete.isEmpty)
    }

    func testNumericVersionComparisonForRuntimes() {
        // 18.10 > 18.9 numericamente (lexicográfico erraria)
        let json = runtimeJSON([
            RuntimeFixture(id: "AAA", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-9", version: "18.9"),
            RuntimeFixture(id: "BBB", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-10", version: "18.10")
        ])
        let obsolete = IOSSimulatorsCleaningService.obsoleteRuntimes(fromJSON: json)
        XCTAssertEqual(obsolete.map(\.identifier), ["AAA"])
    }

    func testMalformedRuntimeJSONYieldsEmpty() {
        XCTAssertTrue(IOSSimulatorsCleaningService.obsoleteRuntimes(fromJSON: "not json").isEmpty)
        XCTAssertTrue(IOSSimulatorsCleaningService.obsoleteRuntimes(fromJSON: "").isEmpty)
    }

    // MARK: - Android NDK

    func testOldNdkVersionsKeepsNewest() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("maclimpo-ndk-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        for version in ["26.1.10909125", "27.0.12077973", "27.1.12297006"] {
            try fm.createDirectory(at: root.appendingPathComponent(version), withIntermediateDirectories: true)
        }

        let old = AndroidSDKCleaningService.oldNdkVersions(atPath: root.path)
        XCTAssertEqual(old, ["26.1.10909125", "27.0.12077973"])
    }

    func testOldNdkVersionsIgnoresNonNumericEntries() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("maclimpo-ndk-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        for name in ["27.1.12297006", ".DS_Store", "notes.txt"] {
            try fm.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }

        XCTAssertTrue(AndroidSDKCleaningService.oldNdkVersions(atPath: root.path).isEmpty)
    }

    func testMissingNdkDirYieldsEmpty() {
        XCTAssertTrue(AndroidSDKCleaningService.oldNdkVersions(atPath: "/tmp/nao-existe-\(UUID())").isEmpty)
    }

    private let fm = FileManager.default
}
