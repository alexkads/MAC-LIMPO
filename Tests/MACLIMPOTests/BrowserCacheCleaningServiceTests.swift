import XCTest
@testable import MAC_LIMPO

final class BrowserCacheCleaningServiceTests: XCTestCase {
    func testChromiumProfileNamesPicksDefaultAndProfiles() {
        let contents = ["Default", "Profile 1", "Profile 3", "System Profile", "Local State", "Crashpad"]
        let profiles = BrowserCacheCleaningService.chromiumProfileNames(from: contents)
        XCTAssertEqual(profiles, ["Default", "Profile 1", "Profile 3"])
    }

    func testChromiumProfileNamesExcludesNonProfiles() {
        // "System Profile" não começa com "Profile "; não deve entrar.
        let profiles = BrowserCacheCleaningService.chromiumProfileNames(from: ["System Profile", "Guest Profile"])
        XCTAssertTrue(profiles.isEmpty)
    }

    func testChromiumProfileNamesEmpty() {
        XCTAssertTrue(BrowserCacheCleaningService.chromiumProfileNames(from: []).isEmpty)
    }
}
