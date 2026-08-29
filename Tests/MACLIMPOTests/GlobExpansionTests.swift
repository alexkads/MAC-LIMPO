import XCTest
@testable import MAC_LIMPO

/// Testa a expansão rasa de glob que substituiu a enumeração recursiva do
/// SystemDataCleaningService (que levava minutos em ~/Library/Containers).
final class GlobExpansionTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("maclimpo-glob-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func makeDirs(_ relPaths: [String]) throws {
        for rel in relPaths {
            try fm.createDirectory(at: root.appendingPathComponent(rel), withIntermediateDirectories: true)
        }
    }

    func testStarExpandsOneLevelOnly() throws {
        try makeDirs([
            "Containers/app.one/Data/Library/Caches",
            "Containers/app.two/Data/Library/Caches",
            "Containers/app.three/Data/Library/Logs", // sem Caches
            "Containers/app.one/Data/Library/Caches/nested/Caches" // não deve casar (profundidade extra)
        ])

        let found = SystemDataCleaningService.expandGlob("\(root.path)/Containers/*/Data/Library/Caches")
        let names = found.map { path in
            path.replacingOccurrences(of: root.path + "/Containers/", with: "")
        }.sorted()
        XCTAssertEqual(names, ["app.one/Data/Library/Caches", "app.two/Data/Library/Caches"])
    }

    func testPartialWildcardComponentUsesFnmatch() throws {
        try makeDirs(["Mail/V10/MailData", "Mail/V9/MailData", "Mail/Attachments"])

        let found = SystemDataCleaningService.expandGlob("\(root.path)/Mail/V*/MailData")
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found.allSatisfy { $0.hasSuffix("/MailData") })
    }

    func testNoMatchesYieldsEmpty() throws {
        try makeDirs(["Containers/app.one/Data"])
        let found = SystemDataCleaningService.expandGlob("\(root.path)/Containers/*/Inexistente")
        XCTAssertTrue(found.isEmpty)
    }

    func testPatternWithoutWildcardIsReturnedAsIs() {
        let path = "\(root.path)/qualquer/coisa"
        XCTAssertEqual(SystemDataCleaningService.expandGlob(path), [path])
    }
}
