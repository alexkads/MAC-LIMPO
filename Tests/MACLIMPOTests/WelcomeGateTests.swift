import XCTest
@testable import MAC_LIMPO

/// Quando as boas-vindas aparecem: aberto por um instalador ou na primeira
/// execução, nunca numa abertura comum nem em retratos de desenvolvimento.
final class WelcomeGateTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "WelcomeGateTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testFirstLaunchShowsWelcome() {
        XCTAssertTrue(WelcomeGate.shouldShow(arguments: ["MAC-LIMPO"], environment: [:], defaults: defaults))
    }

    func testOrdinaryLaunchAfterwardsDoesNot() {
        defaults.set(true, forKey: WelcomeGate.shownKey)
        XCTAssertFalse(WelcomeGate.shouldShow(arguments: ["MAC-LIMPO"], environment: [:], defaults: defaults))
    }

    func testInstallerLaunchAlwaysShowsWelcome() {
        defaults.set(true, forKey: WelcomeGate.shownKey)
        XCTAssertTrue(WelcomeGate.shouldShow(arguments: ["MAC-LIMPO", "--welcome"], environment: [:], defaults: defaults))
    }

    func testDevelopmentSnapshotsSkipWelcome() {
        for key in ["MACLIMPO_SNAPSHOT_POPOVER", "MACLIMPO_OPEN_XRAY", "MACLIMPO_XRAY_ROOT"] {
            XCTAssertFalse(WelcomeGate.shouldShow(arguments: ["MAC-LIMPO"], environment: [key: "x"], defaults: defaults), key)
        }
    }

    func testEnvironmentOverride() {
        defaults.set(true, forKey: WelcomeGate.shownKey)
        XCTAssertTrue(WelcomeGate.shouldShow(arguments: [], environment: ["MACLIMPO_WELCOME": "1"], defaults: defaults))
        XCTAssertFalse(WelcomeGate.shouldShow(arguments: ["--welcome"], environment: ["MACLIMPO_WELCOME": "0"], defaults: defaults))
    }
}
