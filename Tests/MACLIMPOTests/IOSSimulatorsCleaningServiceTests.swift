import XCTest
@testable import MAC_LIMPO

final class IOSSimulatorsCleaningServiceTests: XCTestCase {
    private typealias Service = IOSSimulatorsCleaningService

    /// Formato de `xcrun simctl list devices -j` (campos irrelevantes omitidos).
    private let json = """
    {
      "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
          { "udid": "BOOTED", "name": "iPhone 17 Pro Max", "state": "Booted",
            "isAvailable": true, "dataPathSize": 3991977984 },
          { "udid": "OFF", "name": "iPhone 16", "state": "Shutdown",
            "isAvailable": true, "dataPathSize": 1500000000 },
          { "udid": "FRESH", "name": "iPad Air", "state": "Shutdown",
            "isAvailable": true, "dataPathSize": 0 }
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
          { "udid": "GONE", "name": "iPhone 15", "state": "Shutdown",
            "isAvailable": false, "dataPathSize": 800000000,
            "availabilityError": "runtime profile not found" }
        ]
      }
    }
    """

    func testParsesDevicesWithRuntimeNameAndSize() {
        let devices = Service.devices(fromJSON: json)
        XCTAssertEqual(devices.count, 4)
        let booted = devices.first { $0.udid == "BOOTED" }
        XCTAssertEqual(booted?.runtime, "iOS 26.5")
        XCTAssertEqual(booted?.dataSize, 3_991_977_984)
        XCTAssertEqual(booted?.state, "Booted")
    }

    /// Regressão: com o único simulador ligado, o card mostrava 4 GB e a limpeza
    /// falhava (`erase all` recusa simulador ligado). Ligado fica fora do total.
    func testBootedDeviceIsNeverErasedNorCounted() {
        let plan = Service.plan(for: Service.devices(fromJSON: json))
        XCTAssertEqual(plan.inUse.map(\.udid), ["BOOTED"])
        XCTAssertFalse(plan.erase.contains { $0.udid == "BOOTED" })
        XCTAssertEqual(plan.cleanableSize, 1_500_000_000 + 800_000_000)
    }

    func testPlanSplitsUnavailableShutdownAndSkipsEmpty() {
        let plan = Service.plan(for: Service.devices(fromJSON: json))
        XCTAssertEqual(plan.delete.map(\.udid), ["GONE"])
        XCTAssertEqual(plan.erase.map(\.udid), ["OFF"], "dispositivo sem dados não entra")
    }

    func testOnlyBootedDeviceMeansNothingToClean() {
        let onlyBooted = """
        {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
          {"udid": "B", "name": "iPhone", "state": "Booted", "isAvailable": true, "dataPathSize": 4000}
        ]}}
        """
        let plan = Service.plan(for: Service.devices(fromJSON: onlyBooted))
        XCTAssertEqual(plan.cleanableSize, 0)
        XCTAssertEqual(plan.inUse.count, 1)
    }

    func testInvalidJSONYieldsNoDevices() {
        XCTAssertTrue(Service.devices(fromJSON: "not json").isEmpty)
        XCTAssertTrue(Service.devices(fromJSON: "{}").isEmpty)
    }

    // MARK: - Runtimes órfãos (AssetsV2)

    func testOrphanAssetIsTheOneNoRuntimeUses() {
        let root = "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime"
        let used = "\(root)/26c9174130fa5962f3e60f2a49963194dadbae4c.asset"
        let orphan = "\(root)/fb8de9a3438213a1dda310a6ab5eac9ddf8db858.asset"
        let result = IOSSimulatorsCleaningService.orphanAssetPaths(
            [used, orphan], registeredImagePaths: ["\(used)/AssetData"]
        )
        XCTAssertEqual(result, [orphan])
    }

    func testAssetPrefixMustMatchWholeFolderName() {
        // "abc.asset" não pode ser considerado usado por "abc.asset2/AssetData".
        let result = IOSSimulatorsCleaningService.orphanAssetPaths(
            ["/a/abc.asset"], registeredImagePaths: ["/a/abc.asset2/AssetData"]
        )
        XCTAssertEqual(result, ["/a/abc.asset"])
    }

    func testRegisteredImagePathsRejectsUnexpectedJSON() {
        XCTAssertNil(IOSSimulatorsCleaningService.registeredImagePaths(fromJSON: "not json"))
        XCTAssertEqual(
            IOSSimulatorsCleaningService.registeredImagePaths(fromJSON: #"{"X": {"path": "/p/AssetData"}}"#),
            ["/p/AssetData"]
        )
    }
}
