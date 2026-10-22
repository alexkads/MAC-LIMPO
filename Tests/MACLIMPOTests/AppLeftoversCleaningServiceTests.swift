import XCTest
@testable import MAC_LIMPO

/// Quando os dados de um app contam como sobra. Os itens são criados agora e o
/// teste olha "daqui a 120 dias", quando estão parados há 120 dias.
final class AppLeftoversCleaningServiceTests: XCTestCase {
    private typealias Service = AppLeftoversCleaningService

    private var root: URL!
    private let fm = FileManager.default
    private let later = Date().addingTimeInterval(120 * 86400)

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("maclimpo-leftovers-\(UUID().uuidString)")
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

    private func rule(_ folder: String, aggressive: Bool = false) -> Service.Rule {
        Service.Rule(
            name: folder,
            path: root.appendingPathComponent(folder).path,
            bundleIDs: [],
            appNames: [],
            aggressive: aggressive
        )
    }

    private func leftoverNames(_ rules: [Service.Rule], aggressiveMode: Bool = false, installed: Set<String> = []) -> [String] {
        Service.leftovers(rules: rules, aggressiveMode: aggressiveMode, now: later) { installed.contains($0.name) }
            .map { ($0.path as NSString).lastPathComponent }
    }

    func testOnlyIdleDataOfMissingAppsIsALeftover() throws {
        try make("Gone/settings.json")
        try make("Installed/settings.json")
        try make("InUse/settings.json")
        try make("InUse/state/session.db", modified: later.addingTimeInterval(-86400))

        let rules = [rule("Gone"), rule("Installed"), rule("InUse"), rule("Missing")]
        XCTAssertEqual(leftoverNames(rules, installed: ["Installed"]), ["Gone"])
    }

    /// O Toolbox antigo guarda as próprias IDEs na pasta de dados.
    func testFolderHoldingAnAppIsNeverALeftover() throws {
        try make("Toolbox/apps/IDEA/ch-0/IntelliJ IDEA.app/Contents/Info.plist")

        XCTAssertEqual(leftoverNames([rule("Toolbox")]), [])
    }

    func testLargeSharedDataNeedsAggressiveMode() throws {
        try make("Android/sdk/platform-tools/adb")

        XCTAssertEqual(leftoverNames([rule("Android", aggressive: true)]), [])
        XCTAssertEqual(leftoverNames([rule("Android", aggressive: true)], aggressiveMode: true), ["Android"])
    }

    func testGlobRulesMatchEveryVersion() throws {
        try make("AndroidStudio2024.1/options.xml")
        try make("AndroidStudio2025.1/options.xml")
        try make("Other/options.xml")

        XCTAssertEqual(leftoverNames([rule("AndroidStudio*")]), ["AndroidStudio2024.1", "AndroidStudio2025.1"])
    }

    // MARK: - JetBrains

    func testJetBrainsProductIsTheWholeNameBeforeTheVersion() {
        XCTAssertEqual(Service.jetBrainsProduct(ofFolder: "PyCharmCE2024.3"), "PyCharmCE")
        XCTAssertEqual(Service.jetBrainsProduct(ofFolder: "PyCharm2024.3"), "PyCharm")
        XCTAssertEqual(Service.jetBrainsProduct(ofFolder: "IntelliJIdea2025.1"), "IntelliJIdea")
        XCTAssertNil(Service.jetBrainsProduct(ofFolder: "consentOptions"))
        XCTAssertNil(Service.jetBrainsProduct(ofFolder: "Rustrover"))
    }

    func testJetBrainsRulesOnlyForKnownVersionedProducts() throws {
        for folder in ["PyCharmCE2024.3", "WebStorm2025.1", "bl", "Unknown2024.1"] {
            try fm.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }

        let rules = Service.jetBrainsRules(in: root.path)
        XCTAssertEqual(rules.map(\.name), ["JetBrains PyCharmCE2024.3", "JetBrains WebStorm2025.1"])
        XCTAssertEqual(rules.first?.bundleIDs, ["com.jetbrains.pycharm.ce"])
    }
}
