@testable import MAC_LIMPO
import XCTest

final class HomebrewCleaningServiceTests: XCTestCase {
    func testParsesFreedSpace() {
        let output = "Would remove: /opt/homebrew/Cellar/node/22.1.0 (2,345 files, 80MB)\n" +
            "==> This operation would free approximately 1.5GB of disk space."
        XCTAssertEqual(HomebrewCleaningService.freedBytes(fromCleanupOutput: output), Int64(1.5 * 1024 * 1024 * 1024))
        XCTAssertEqual(HomebrewCleaningService.freedBytes(fromCleanupOutput: "nothing"), 0)
    }

    func testParsesBrokenLinks() {
        let output = "Would remove (broken link): /opt/homebrew/bin/dart\nWould remove (broken link): /opt/homebrew/bin/flutter"
        XCTAssertEqual(HomebrewCleaningService.brokenLinks(fromCleanupOutput: output), ["dart", "flutter"])
    }

    func testParsesAutoremoveList() {
        let output = "==> Would autoremove 2 unneeded formulae:\nlibfoo\nlibbar\n"
        XCTAssertEqual(HomebrewCleaningService.autoremovable(fromOutput: output), ["libfoo", "libbar"])
        XCTAssertEqual(HomebrewCleaningService.autoremovable(fromOutput: ""), [])
    }
}
