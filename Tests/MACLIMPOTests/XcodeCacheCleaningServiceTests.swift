import XCTest
@testable import MAC_LIMPO

final class XcodeCacheCleaningServiceTests: XCTestCase {
    /// Archives guardam os dSYMs das versões publicadas, e
    /// ~/Library/org.swift.swiftpm é configuração do SwiftPM — nenhum é cache.
    func testArchivesAndSwiftPMConfigurationAreNeverTargeted() {
        let paths = XcodeCacheCleaningService.xcodePaths
        XCTAssertFalse(paths.contains { $0.hasSuffix("/Xcode/Archives") })
        XCTAssertFalse(paths.contains("~/Library/org.swift.swiftpm"))
        XCTAssertTrue(paths.contains("~/Library/Developer/Xcode/DerivedData"))
    }
}
