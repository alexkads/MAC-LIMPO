import XCTest
@testable import MAC_LIMPO

final class NvmCleaningServiceTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("maclimpo-nvm-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func makeVersions(_ versions: [String], defaultAlias: String? = nil) throws -> (String, String) {
        let versionsDir = root.appendingPathComponent("versions/node")
        for version in versions {
            try fm.createDirectory(
                at: versionsDir.appendingPathComponent(version),
                withIntermediateDirectories: true
            )
        }
        let aliasFile = root.appendingPathComponent("alias/default")
        if let alias = defaultAlias {
            try fm.createDirectory(at: aliasFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try alias.write(to: aliasFile, atomically: true, encoding: .utf8)
        }
        return (versionsDir.path, aliasFile.path)
    }

    func testKeepsNewestPerMajorRemovesRest() throws {
        let (dir, alias) = try makeVersions(
            ["v18.19.1", "v18.20.8", "v20.11.1", "v20.19.0", "v22.9.0", "v22.23.2"],
            defaultAlias: "22"
        )
        let targets = NvmCleaningService.obsoleteVersionTargets(versionsDir: dir, defaultAliasFile: alias)
        let removed = targets.map { ($0.path as NSString).lastPathComponent }.sorted()
        XCTAssertEqual(removed, ["v18.19.1", "v20.11.1", "v22.9.0"])
    }

    func testNumericMajorOrderingBeatsLexicographic() throws {
        // v22.10.0 > v22.9.0 numericamente (lexicográfico erraria)
        let (dir, alias) = try makeVersions(["v22.9.0", "v22.10.0"])
        let targets = NvmCleaningService.obsoleteVersionTargets(versionsDir: dir, defaultAliasFile: alias)
        XCTAssertEqual(targets.map { ($0.path as NSString).lastPathComponent }, ["v22.9.0"])
    }

    func testExactVersionDefaultAliasIsProtected() throws {
        let (dir, alias) = try makeVersions(
            ["v20.11.1", "v20.19.0"],
            defaultAlias: "v20.11.1"
        )
        let targets = NvmCleaningService.obsoleteVersionTargets(versionsDir: dir, defaultAliasFile: alias)
        XCTAssertTrue(targets.isEmpty, "alias default exato não pode ser removido")
    }

    func testMissingNvmDirYieldsNoTargets() {
        let targets = NvmCleaningService.obsoleteVersionTargets(
            versionsDir: root.appendingPathComponent("nao-existe").path,
            defaultAliasFile: root.appendingPathComponent("nem-esse").path
        )
        XCTAssertTrue(targets.isEmpty)
    }
}
