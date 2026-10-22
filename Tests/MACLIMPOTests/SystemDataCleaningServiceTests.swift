import XCTest
@testable import MAC_LIMPO

/// Snapshots locais do Time Machine são pontos de restauração: só o modo
/// agressivo os apaga.
final class TimeMachineSnapshotTests: XCTestCase {
    private let listing = """
    Snapshots for disk /:
    com.apple.TimeMachine.2026-10-20-101010.local
    com.apple.TimeMachine.2026-10-21-111111.local
    """

    func testSnapshotsAreKeptOutsideAggressiveMode() {
        XCTAssertNil(SystemDataCleaningService.timeMachineDeletionScript(listing: listing, aggressiveMode: false))
    }

    func testAggressiveModeDeletesThemWithOnePasswordPrompt() throws {
        let script = try XCTUnwrap(SystemDataCleaningService.timeMachineDeletionScript(listing: listing, aggressiveMode: true))
        XCTAssertEqual(
            script,
            #"do shell script "tmutil deletelocalsnapshots 2026-10-20-101010; tmutil deletelocalsnapshots 2026-10-21-111111" with administrator privileges"#
        )
    }

    func testNothingToDeleteGivesNoScript() {
        XCTAssertNil(SystemDataCleaningService.timeMachineDeletionScript(listing: "Snapshots for disk /:\n", aggressiveMode: true))
    }

    /// Só datas no formato do tmutil chegam ao shell.
    func testUnexpectedNamesNeverReachTheShell() {
        let hostile = "com.apple.TimeMachine.2026-10-20-101010; rm -rf ~.local\n"
        XCTAssertNil(SystemDataCleaningService.timeMachineDeletionScript(listing: hostile, aggressiveMode: true))
    }
}
