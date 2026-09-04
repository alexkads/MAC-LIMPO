import XCTest
@testable import MAC_LIMPO

/// Extensões obsoletas e histórico local antigo (`IDECacheCleaningService`).
final class IDECacheCleaningServiceTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("maclimpo-ide-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func makeExtensions(_ present: [String], obsolete: [String]?) throws -> String {
        let dir = root.appendingPathComponent("extensions")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in present {
            try fm.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        if let obsolete {
            let json = Dictionary(uniqueKeysWithValues: obsolete.map { ($0, true) })
            let data = try JSONSerialization.data(withJSONObject: json)
            try data.write(to: dir.appendingPathComponent(".obsolete"))
        }
        return dir.path
    }

    // MARK: - .obsolete

    func testReturnsOnlyMarkedExtensionsThatStillExist() throws {
        let dir = try makeExtensions(
            [
                "openai.chatgpt-26.825.51511-darwin-arm64",
                "openai.chatgpt-26.901.22334-darwin-arm64",
                "prisma.prisma-31.12.2"
            ],
            obsolete: ["openai.chatgpt-26.825.51511-darwin-arm64", "already.deleted-1.0.0"]
        )
        let paths = IDECacheCleaningService.obsoleteExtensionPaths(extensionsDir: dir)
        XCTAssertEqual(paths.map { ($0 as NSString).lastPathComponent }, ["openai.chatgpt-26.825.51511-darwin-arm64"])
    }

    func testNewerVersionIsNeverInferredAsObsolete() throws {
        // Duas versões instaladas mas nenhuma marcada: o editor ainda não decidiu.
        let dir = try makeExtensions(["a.b-1.0.0", "a.b-2.0.0"], obsolete: [])
        XCTAssertTrue(IDECacheCleaningService.obsoleteExtensionPaths(extensionsDir: dir).isEmpty)
    }

    func testMissingMarkerYieldsNothing() throws {
        let dir = try makeExtensions(["a.b-1.0.0"], obsolete: nil)
        XCTAssertTrue(IDECacheCleaningService.obsoleteExtensionPaths(extensionsDir: dir).isEmpty)
    }

    func testMarkerCannotEscapeExtensionsDir() throws {
        // Um .obsolete adulterado com "../" não pode virar alvo de remoção.
        let dir = try makeExtensions([], obsolete: ["../outside", "..", "."])
        XCTAssertTrue(IDECacheCleaningService.obsoleteExtensionPaths(extensionsDir: dir).isEmpty)
    }

    // MARK: - Histórico local

    func testOnlyEntriesOlderThanCutoffAreStale() throws {
        let history = root.appendingPathComponent("History")
        let old = history.appendingPathComponent("old")
        let recent = history.appendingPathComponent("recent")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try fm.createDirectory(at: recent, withIntermediateDirectories: true)
        let hundredDaysAgo = Date().addingTimeInterval(-100 * 86400)
        try fm.setAttributes([.modificationDate: hundredDaysAgo], ofItemAtPath: old.path)

        let stale = IDECacheCleaningService.staleLocalHistoryPaths(historyDir: history.path, maxAgeDays: 90)
        XCTAssertEqual(stale.map { ($0 as NSString).lastPathComponent }, ["old"])
    }

    func testMissingHistoryDirYieldsNothing() {
        let stale = IDECacheCleaningService.staleLocalHistoryPaths(
            historyDir: root.appendingPathComponent("nope").path
        )
        XCTAssertTrue(stale.isEmpty)
    }
}

/// Atualização do Docker Desktop em staging: só é lixo quando não é mais nova
/// que a instalada.
final class DockerStagedInstallerTests: XCTestCase {
    func testPendingUpdateIsPreserved() {
        // Caso real da máquina: 4.89.0 baixado, 4.81.0 instalado → pendente.
        XCTAssertFalse(DockerCleaningService.isStagedInstallerStale(
            stagedVersion: "4.89.0",
            installedVersion: "4.81.0"
        ))
    }

    func testAlreadyInstalledVersionIsStale() {
        XCTAssertTrue(DockerCleaningService.isStagedInstallerStale(stagedVersion: "4.81.0", installedVersion: "4.81.0"))
        XCTAssertTrue(DockerCleaningService.isStagedInstallerStale(stagedVersion: "4.79.0", installedVersion: "4.81.0"))
    }

    func testNumericComparison() {
        XCTAssertFalse(DockerCleaningService.isStagedInstallerStale(
            stagedVersion: "4.100.0",
            installedVersion: "4.99.0"
        ))
    }

    func testUnknownVersionsArePreserved() {
        XCTAssertFalse(DockerCleaningService.isStagedInstallerStale(stagedVersion: nil, installedVersion: "4.81.0"))
        XCTAssertFalse(DockerCleaningService.isStagedInstallerStale(stagedVersion: "4.89.0", installedVersion: nil))
        XCTAssertFalse(DockerCleaningService.isStagedInstallerStale(stagedVersion: "", installedVersion: ""))
    }
}
