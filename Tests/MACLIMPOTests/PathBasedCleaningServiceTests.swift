import XCTest
@testable import MAC_LIMPO

final class PathBasedCleaningServiceTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("maclimpo-pbcs-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func makeFile(_ relPath: String, bytes: Int, modifiedDaysAgo: Int? = nil) throws -> URL {
        let url = root.appendingPathComponent(relPath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0, count: bytes).write(to: url)
        if let days = modifiedDaysAgo {
            let date = Date().addingTimeInterval(-Double(days) * 86400)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return url
    }

    /// Base direta p/ testar; useTrash:false apaga em tmp sem poluir a Lixeira real.
    private func service(_ targets: [CleanTarget]) -> PathBasedCleaningService {
        PathBasedCleaningService(category: .homebrew, targets: targets, useTrash: false)
    }

    // MARK: - removeItem

    func testRemoveItemDeletesWholeDirectory() async throws {
        try makeFile("cache/a.bin", bytes: 100_000)
        try makeFile("cache/b.bin", bytes: 100_000)
        let dir = root.appendingPathComponent("cache").path

        let svc = service([CleanTarget(dir)])
        let scan = await svc.scan(progress: nil)
        XCTAssertGreaterThan(scan.estimatedSize, 0)

        let result = await svc.clean()
        XCTAssertTrue(result.success)
        XCTAssertGreaterThan(result.bytesRemoved, 0)
        XCTAssertFalse(fm.fileExists(atPath: dir), "diretório inteiro deve ser removido")
    }

    // MARK: - removeContents

    func testRemoveContentsPreservesParentDir() async throws {
        try makeFile("keep/x.bin", bytes: 50000)
        try makeFile("keep/y.bin", bytes: 50000)
        let dir = root.appendingPathComponent("keep").path

        let svc = service([CleanTarget(dir, strategy: .removeContents)])
        let result = await svc.clean()

        XCTAssertTrue(result.success)
        XCTAssertTrue(fm.fileExists(atPath: dir), "a pasta pai deve ser preservada")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir).count, 0, "os filhos devem ser removidos")
    }

    // MARK: - age filter

    func testOlderThanDaysOnlyRemovesOldChildren() async throws {
        _ = try makeFile("logs/old.log", bytes: 10000, modifiedDaysAgo: 40)
        let fresh = try makeFile("logs/new.log", bytes: 10000, modifiedDaysAgo: 1)
        let dir = root.appendingPathComponent("logs").path

        let svc = service([CleanTarget(dir, strategy: .removeContents, olderThanDays: 30)])
        let result = await svc.clean()

        XCTAssertTrue(result.success)
        XCTAssertTrue(fm.fileExists(atPath: fresh.path), "arquivo recente NÃO deve ser removido")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir), ["new.log"])
    }

    // MARK: - missing paths

    func testMissingTargetsAreSkippedCleanly() async {
        let svc = service([CleanTarget("/nonexistent/maclimpo/\(UUID().uuidString)")])
        let scan = await svc.scan(progress: nil)
        let result = await svc.clean()
        XCTAssertEqual(scan.estimatedSize, 0)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.bytesRemoved, 0)
    }
}
