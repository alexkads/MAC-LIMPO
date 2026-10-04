import XCTest
@testable import MAC_LIMPO

/// Regras de retenção do .NET. Os nomes abaixo são as pastas reais de uma
/// instalação com vários anos de `.pkg` acumulados.
final class DotnetSdkCleaningServiceTests: XCTestCase {
    // MARK: - Parsing

    func testParsesStableVersions() {
        XCTAssertEqual(DotnetSdkCleaningService.stableVersionNumbers("6.0.421"), [6, 0, 421])
        XCTAssertEqual(DotnetSdkCleaningService.stableVersionNumbers("10.0.100"), [10, 0, 100])
    }

    func testIgnoresPreviewsAndNonVersions() {
        XCTAssertNil(DotnetSdkCleaningService.stableVersionNumbers("10.0.100-rc.1.25451.107"))
        XCTAssertNil(DotnetSdkCleaningService.stableVersionNumbers("NuGetFallbackFolder"))
        XCTAssertNil(DotnetSdkCleaningService.stableVersionNumbers("6.0"))
        XCTAssertNil(DotnetSdkCleaningService.stableVersionNumbers(""))
    }

    // MARK: - SDKs: feature band

    func testSdkKeepsNewestPerFeatureBand() {
        let installed = [
            "6.0.412", "6.0.413", "6.0.421",
            "7.0.306", "7.0.315",
            "8.0.203", "8.0.204",
            "9.0.100", "9.0.102", "9.0.305", "9.0.306"
        ]
        let removed = DotnetSdkCleaningService.obsoleteVersions(among: installed, rule: .featureBand)
        XCTAssertEqual(removed, ["6.0.412", "6.0.413", "7.0.306", "8.0.203", "9.0.100", "9.0.305"])
    }

    func testSdkFeatureBandsAreIndependent() {
        // 9.0.1xx e 9.0.3xx são bands distintos: um global.json com
        // rollForward latestPatch preso em 9.0.1xx precisa que 9.0.102 fique.
        let removed = DotnetSdkCleaningService.obsoleteVersions(among: ["9.0.102", "9.0.306"], rule: .featureBand)
        XCTAssertTrue(removed.isEmpty)
    }

    // MARK: - Runtimes e packs: major.minor

    func testRuntimeKeepsNewestPerMinor() {
        let installed = [
            "6.0.20",
            "6.0.29",
            "6.0.9",
            "7.0.10",
            "7.0.18",
            "7.0.9",
            "8.0.3",
            "8.0.4",
            "9.0.0",
            "9.0.10",
            "9.0.9"
        ]
        let removed = DotnetSdkCleaningService.obsoleteVersions(among: installed, rule: .minor)
        XCTAssertEqual(removed, ["6.0.9", "6.0.20", "7.0.9", "7.0.10", "8.0.3", "9.0.0", "9.0.9"])
    }

    func testNumericOrderingBeatsLexicographic() {
        // "9.0.10" > "9.0.9" numericamente; lexicográfico manteria o errado.
        let removed = DotnetSdkCleaningService.obsoleteVersions(among: ["9.0.9", "9.0.10"], rule: .minor)
        XCTAssertEqual(removed, ["9.0.9"])
    }

    func testSingleVersionPerLineIsNeverRemoved() {
        let removed = DotnetSdkCleaningService.obsoleteVersions(among: ["6.0.29", "7.0.18", "8.0.4"], rule: .minor)
        XCTAssertTrue(removed.isEmpty)
    }

    func testPreviewsAreNeverRemoved() {
        let removed = DotnetSdkCleaningService.obsoleteVersions(
            among: ["10.0.100-preview.7", "10.0.100-rc.1", "10.0.100"],
            rule: .featureBand
        )
        XCTAssertTrue(removed.isEmpty)
    }

    // MARK: - Modo agressivo

    private let october2026 = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!

    func testAggressiveRemovesOutOfSupportAndSupersededBands() {
        let installed = ["6.0.421", "7.0.315", "8.0.204", "9.0.102", "9.0.306", "10.0.401"]
        let removed = DotnetSdkCleaningService.aggressiveSDKRemovals(among: installed, pinnedBands: [], now: october2026)
        XCTAssertEqual(removed, ["6.0.421", "7.0.315", "9.0.102"])
    }

    func testAggressiveKeepsPinnedBandAndNewestOverall() {
        let installed = ["6.0.421", "9.0.102", "9.0.306"]
        let removed = DotnetSdkCleaningService.aggressiveSDKRemovals(
            among: installed, pinnedBands: ["6.0.4", "9.0.1"], now: october2026
        )
        XCTAssertEqual(removed, [])
        // Mesmo todos fora de suporte, o mais novo instalado fica.
        let old = DotnetSdkCleaningService.aggressiveSDKRemovals(among: ["6.0.100", "7.0.100"], pinnedBands: [], now: october2026)
        XCTAssertEqual(old, ["6.0.100"])
    }

    func testProjectUsageDetectsMobileAndLegacyAspire() {
        var usage = DotnetSdkCleaningService.ProjectUsage()
        DotnetSdkCleaningService.absorb(projectFile: "<TargetFramework>net9.0</TargetFramework>", into: &usage)
        XCTAssertFalse(usage.usesMobile)
        DotnetSdkCleaningService.absorb(projectFile: "<Project Sdk=\"Aspire.AppHost.Sdk/9.1.0\"><IsAspireHost>true</IsAspireHost>", into: &usage)
        XCTAssertFalse(usage.usesAspireWorkload)
        DotnetSdkCleaningService.absorb(projectFile: "<TargetFrameworks>net9.0-ios;net9.0-android</TargetFrameworks>", into: &usage)
        XCTAssertTrue(usage.usesMobile)
        DotnetSdkCleaningService.absorb(globalJSON: #"{"sdk":{"version":"10.0.301","rollForward":"latestFeature"}}"#, into: &usage)
        XCTAssertEqual(usage.pinnedBands, ["10.0.3"])
    }

    func testUnusedWorkloadsKeepUnknownOnes() {
        let none = DotnetSdkCleaningService.ProjectUsage()
        XCTAssertEqual(DotnetSdkCleaningService.unusedWorkloads(["maui", "aspire", "wasm-tools"], usage: none), ["aspire", "maui"])
        var mobile = none
        mobile.usesMobile = true
        XCTAssertEqual(DotnetSdkCleaningService.unusedWorkloads(["maui", "ios"], usage: mobile), [])
    }
}
