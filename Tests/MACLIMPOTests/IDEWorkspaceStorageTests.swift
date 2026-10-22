import XCTest
@testable import MAC_LIMPO

/// workspaceStorage do VS Code/Cursor: só sai o de projeto que sumiu. Os itens
/// são criados agora e o teste olha "daqui a 90 dias".
final class IDEWorkspaceStorageTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default
    private let later = Date().addingTimeInterval(90 * 86400)

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("maclimpo-wss-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private var storage: URL {
        root.appendingPathComponent("workspaceStorage")
    }

    private func entry(_ name: String, manifest: [String: String]?, modified: Date? = nil) throws {
        let dir = storage.appendingPathComponent(name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("state.vscdb"))
        if let modified {
            try fm.setAttributes([.modificationDate: modified], ofItemAtPath: dir.appendingPathComponent("state.vscdb").path)
        }
        if let manifest {
            try JSONSerialization.data(withJSONObject: manifest).write(to: dir.appendingPathComponent("workspace.json"))
        }
    }

    func testOnlyIdleEntriesOfVanishedLocalProjectsGo() throws {
        let alive = root.appendingPathComponent("My Project")
        try fm.createDirectory(at: alive, withIntermediateDirectories: true)
        let gone = "file:///nonexistent-\(UUID().uuidString)"

        try entry("gone", manifest: ["folder": "\(gone)/proj"])
        try entry("goneWorkspaceFile", manifest: ["workspace": "\(gone)/x.code-workspace"])
        try entry("alive", manifest: ["folder": alive.absoluteString])
        try entry("goneButRecent", manifest: ["folder": "\(gone)/recent"], modified: later.addingTimeInterval(-86400))
        try entry("remote", manifest: ["folder": "vscode-remote://ssh-remote%2Bhost/home/me/proj"])
        try entry("unmountedDisk", manifest: ["folder": "file:///Volumes/NoSuchDisk-\(UUID().uuidString)/proj"])
        try entry("emptyWindow", manifest: nil)

        let orphans = IDECacheCleaningService.orphanedWorkspaceStorage(in: storage.path, now: later)
        XCTAssertEqual(orphans.map { ($0 as NSString).lastPathComponent }, ["gone", "goneWorkspaceFile"])
    }

    func testRecentlyUsedStorageIsKeptEvenIfTheProjectIsGone() throws {
        try entry("gone", manifest: ["folder": "file:///nonexistent-\(UUID().uuidString)"])

        XCTAssertEqual(IDECacheCleaningService.orphanedWorkspaceStorage(in: storage.path, now: Date()), [])
    }
}
