import XCTest
@testable import MAC_LIMPO

/// O que sai do /tmp. Os itens são criados agora e o teste olha "daqui a 30
/// dias"; uma pasta temporária faz o papel do /tmp.
final class TempFilesCleaningServiceTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default
    private let later = Date().addingTimeInterval(30 * 86400)

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("maclimpo-tmp-\(UUID().uuidString)")
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

    private func makeFIFO(_ relPath: String) throws {
        let url = root.appendingPathComponent(relPath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertEqual(mkfifo(url.path, 0o600), 0)
    }

    private func staleNames(owner: uid_t = getuid()) -> [String] {
        TempFilesCleaningService.staleTemporaryItems(in: root.path, now: later, owner: owner)
            .map { ($0 as NSString).lastPathComponent }
    }

    func testOnlyStaleItemsWithoutLiveEndpointsAreTaken() throws {
        try make("old.log")
        try make("stale-dir/a/b.txt")
        try make(".hidden")
        try make("com.apple.launchd.abc/Listeners")
        try make("fresh/file", modified: later.addingTimeInterval(-86400))
        // Sessão viva: tmux e ssh-agent conversam por socket/FIFO aqui dentro.
        try makeFIFO("tmux-501/default")
        try makeFIFO("loose-pipe")

        XCTAssertEqual(staleNames(), ["old.log", "stale-dir"])
    }

    func testItemsOfOtherUsersAreLeftAlone() throws {
        try make("old.log")

        XCTAssertEqual(staleNames(owner: getuid() &+ 1), [])
    }

    /// Scratchpads do Claude Code: uma sessão viva não segura as paradas.
    func testSessionFoldersAreJudgedPerSession() throws {
        let sessions = "claude-\(getuid())"
        try make("\(sessions)/projA/old-session/scratchpad/target/big.rlib")
        try make("\(sessions)/projA/live-session/scratchpad/log", modified: later.addingTimeInterval(-3600))
        try make("\(sessions)/projB/old-session/notes.txt")
        try make("\(sessions)/loose.txt")
        try makeFIFO("\(sessions)/projB/socket-session/pipe")

        let stale = TempFilesCleaningService.staleTemporaryItems(in: root.path, now: later)
            .map { String($0.dropFirst(root.path.count + 1)) }
        XCTAssertEqual(stale, [
            "\(sessions)/loose.txt",
            "\(sessions)/projA/old-session",
            "\(sessions)/projB/old-session"
        ])
    }

    /// Só a pasta do próprio uid é de sessões; a de outro uid é um item comum.
    func testOtherUsersSessionFolderIsAWholeItem() throws {
        try make("claude-\(getuid() &+ 1)/proj/session/file")
        try make("claude-\(getuid())/proj/live/file", modified: later.addingTimeInterval(-3600))

        XCTAssertEqual(staleNames(), ["claude-\(getuid() &+ 1)"])
    }
}
