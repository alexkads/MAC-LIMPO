import XCTest
@testable import MAC_LIMPO

/// Seleção de toolchains rustup superadas (`CargoCleaningService`).
final class CargoToolchainTests: XCTestCase {
    private let triple = "aarch64-apple-darwin"

    // MARK: - Parsing

    func testParsesPinnedVersions() {
        XCTAssertEqual(CargoCleaningService.pinnedVersionNumbers("1.92.0-\(triple)"), [1, 92, 0])
        XCTAssertEqual(CargoCleaningService.pinnedVersionNumbers("1.100.3-\(triple)"), [1, 100, 3])
    }

    func testChannelsAreNotPinnedVersions() {
        XCTAssertNil(CargoCleaningService.pinnedVersionNumbers("stable-\(triple)"))
        XCTAssertNil(CargoCleaningService.pinnedVersionNumbers("nightly-\(triple)"))
        XCTAssertNil(CargoCleaningService.pinnedVersionNumbers("beta-2026-01-01-\(triple)"))
        XCTAssertNil(CargoCleaningService.pinnedVersionNumbers("1.92-\(triple)"))
    }

    // MARK: - settings.toml

    func testReadsDefaultAndOverrides() {
        let settings = """
        version = "12"
        default_toolchain = "1.98.0-aarch64-apple-darwin"
        profile = "default"

        [overrides]
        "/Users/me/legacy" = "1.85.0-aarch64-apple-darwin"
        """
        let protected = CargoCleaningService.protectedToolchains(fromSettings: settings)
        XCTAssertEqual(protected, ["1.98.0-aarch64-apple-darwin", "1.85.0-aarch64-apple-darwin"])
    }

    func testEmptyOverridesSectionProtectsOnlyDefault() {
        let settings = """
        default_toolchain = "stable-aarch64-apple-darwin"

        [overrides]
        """
        XCTAssertEqual(
            CargoCleaningService.protectedToolchains(fromSettings: settings),
            ["stable-aarch64-apple-darwin"]
        )
    }

    // MARK: - Seleção

    func testRemovesOlderPinnedKeepsNewestAndChannels() {
        let installed = ["stable-\(triple)", "nightly-\(triple)", "1.92.0-\(triple)", "1.98.0-\(triple)"]
        let removed = CargoCleaningService.obsoletePinnedToolchains(among: installed, protected: ["1.98.0-\(triple)"])
        XCTAssertEqual(removed, ["1.92.0-\(triple)"])
    }

    func testProtectedOlderPinnedStays() {
        let installed = ["1.85.0-\(triple)", "1.92.0-\(triple)", "1.98.0-\(triple)"]
        let removed = CargoCleaningService.obsoletePinnedToolchains(among: installed, protected: ["1.85.0-\(triple)"])
        XCTAssertEqual(removed, ["1.92.0-\(triple)"])
    }

    func testOnlyChannelsYieldsNothing() {
        let removed = CargoCleaningService.obsoletePinnedToolchains(
            among: ["stable-\(triple)", "nightly-\(triple)"],
            protected: []
        )
        XCTAssertTrue(removed.isEmpty)
    }

    func testNumericOrderingBeatsLexicographic() {
        // 1.100.0 é mais novo que 1.99.0
        let removed = CargoCleaningService.obsoletePinnedToolchains(
            among: ["1.99.0-\(triple)", "1.100.0-\(triple)"],
            protected: []
        )
        XCTAssertEqual(removed, ["1.99.0-\(triple)"])
    }

    // MARK: - Integração com o disco

    func testTargetsFromTemporaryRustupDir() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("maclimpo-rustup-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let toolchains = root.appendingPathComponent("toolchains")
        for name in ["stable-\(triple)", "1.92.0-\(triple)", "1.98.0-\(triple)"] {
            try fm.createDirectory(at: toolchains.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let settings = root.appendingPathComponent("settings.toml")
        try "default_toolchain = \"1.98.0-\(triple)\"\n".write(to: settings, atomically: true, encoding: .utf8)

        let targets = CargoCleaningService.obsoleteToolchainTargets(
            toolchainsDir: toolchains.path,
            settingsFile: settings.path
        )
        XCTAssertEqual(targets.map { ($0.path as NSString).lastPathComponent }, ["1.92.0-\(triple)"])
    }
}
