import XCTest
@testable import MAC_LIMPO

/// Só testa a classificação de paths (string pura). Nada aqui encosta em pastas
/// protegidas: rodar isso do terminal abriria diálogos do TCC.
final class PermissionsHelperTests: XCTestCase {
    private let home = NSHomeDirectory()

    func testContainersRequireFullDiskAccess() {
        XCTAssertTrue(PermissionsHelper.requiresFullDiskAccess(path: "~/Library/Containers"))
        XCTAssertTrue(PermissionsHelper.requiresFullDiskAccess(path: "~/Library/Containers/*/Data/Library/Caches"))
        XCTAssertTrue(PermissionsHelper.requiresFullDiskAccess(path: "~/Library/Group Containers/group.x/Library/Caches"))
        XCTAssertTrue(PermissionsHelper.requiresFullDiskAccess(path: home + "/Library/Safari/History.db"))
    }

    func testUnprotectedPathsDoNotRequireFullDiskAccess() {
        XCTAssertFalse(PermissionsHelper.requiresFullDiskAccess(path: "~/Library/Caches"))
        XCTAssertFalse(PermissionsHelper.requiresFullDiskAccess(path: "~/Library/Logs"))
        XCTAssertFalse(PermissionsHelper.requiresFullDiskAccess(path: home + "/Projects"))
    }

    func testPrefixMatchRespectsPathComponentBoundary() {
        // "ContainersBackup" não é "Containers/…".
        XCTAssertFalse(PermissionsHelper.requiresFullDiskAccess(path: "~/Library/ContainersBackup"))
        XCTAssertFalse(PermissionsHelper.requiresFullDiskAccess(path: "~/Library/Mailbox"))
    }

    func testPathsOutsideHomeAreNotClassified() {
        XCTAssertFalse(PermissionsHelper.requiresFullDiskAccess(path: "/Library/Containers"))
        XCTAssertFalse(PermissionsHelper.requiresFullDiskAccess(path: "/tmp/Library/Containers/x"))
    }
}
