import XCTest
@testable import MAC_LIMPO

/// Quais downloads podem ir para a Lixeira. Os itens são criados agora e o
/// teste olha "daqui a 60 dias", quando eles têm 60 dias.
final class DownloadsCleaningServiceTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default
    private let later = Date().addingTimeInterval(60 * 86400)

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("maclimpo-downloads-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func make(_ relPath: String, modified: Date? = nil) throws {
        let url = root.appendingPathComponent(relPath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        if let modified {
            try fm.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    }

    private func staleNames(now: Date) -> [String] {
        DownloadsCleaningService.staleItems(in: root.path, now: now).map { ($0 as NSString).lastPathComponent }
    }

    func testOldUntouchedItemsAreStale() throws {
        try make("installer.dmg")
        try make("old-folder/a.txt")
        try make(".DS_Store")

        XCTAssertEqual(staleNames(now: later), ["installer.dmg", "old-folder"])
    }

    /// A data da pasta de cima não basta: um arquivo editado lá dentro a protege.
    func testFolderWithRecentFileInsideIsKept() throws {
        try make("project/old.txt")
        try make("project/sub/edited.txt", modified: later.addingTimeInterval(-86400))

        XCTAssertEqual(staleNames(now: later), [])
    }

    func testFreshDownloadsAreKept() throws {
        try make("new.zip")

        XCTAssertEqual(staleNames(now: Date()), [])
    }
}
