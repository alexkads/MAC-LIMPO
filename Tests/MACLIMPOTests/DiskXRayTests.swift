import XCTest
@testable import MAC_LIMPO

@MainActor
final class DiskXRayTests: XCTestCase {
    // MARK: - APFS

    private func apfsPlist() throws -> Data {
        let root: [String: Any] = [
            "Containers": [
                [
                    "CapacityCeiling": 5_000_000_000,
                    "CapacityFree": 2_000_000_000,
                    "Volumes": [["DeviceIdentifier": "disk1s1", "Name": "Recovery", "Roles": ["Recovery"],
                                 "CapacityInUse": 2_500_000_000]]
                ],
                [
                    "CapacityCeiling": 494_000_000_000,
                    "CapacityFree": 150_000_000_000,
                    "Volumes": [
                        ["DeviceIdentifier": "disk3s1", "Name": "Macintosh HD", "Roles": ["System"],
                         "CapacityInUse": 13_000_000_000],
                        ["DeviceIdentifier": "disk3s5", "Name": "Data", "Roles": ["Data"],
                         "CapacityInUse": 300_000_000_000],
                        ["DeviceIdentifier": "disk3s6", "Name": "VM", "Roles": ["VM"],
                         "CapacityInUse": 10_000_000_000],
                        ["DeviceIdentifier": "disk3s2", "Name": "Preboot", "Roles": ["Preboot"],
                         "CapacityInUse": 11_000_000_000]
                    ]
                ]
            ]
        ]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    func testOverviewPicksContainerOfDataVolumeAndClosesTheAccount() throws {
        let overview = try XCTUnwrap(DiskOverview.parse(plist: apfsPlist(), dataDevice: "disk3s5"))
        XCTAssertEqual(overview.capacity, 494_000_000_000)
        XCTAssertEqual(overview.dataVolume?.bytes, 300_000_000_000)
        XCTAssertEqual(overview.volumes.first?.role, .data, "maior volume primeiro")
        // Volumes + overhead + livre = capacidade, sem sobra.
        let volumes = overview.volumes.reduce(0) { $0 + $1.bytes }
        XCTAssertEqual(volumes + overview.containerOverhead + overview.free, overview.capacity)
        XCTAssertEqual(overview.containerOverhead, 10_000_000_000)
    }

    func testOverviewReturnsNilForUnknownDevice() throws {
        XCTAssertNil(try DiskOverview.parse(plist: apfsPlist(), dataDevice: "disk9s9"))
    }

    // MARK: - Firmlinks

    func testFirmlinksMapDataPathsToVisiblePaths() {
        let links = Firmlinks(contents: "/Users\tUsers\n/usr/local\tusr/local\n/System/Library/AssetsV2\tSystem/Library/AssetsV2\n")
        XCTAssertEqual(links.displayPath("/System/Volumes/Data/Users/me/x"), "/Users/me/x")
        XCTAssertEqual(links.displayPath("/System/Volumes/Data/usr/local/bin"), "/usr/local/bin")
        XCTAssertEqual(
            links.displayPath("/System/Volumes/Data/System/Library/AssetsV2/runtime"),
            "/System/Library/AssetsV2/runtime"
        )
        XCTAssertEqual(links.displayPath("/System/Volumes/Data/UsersX"), "/System/Volumes/Data/UsersX")
        XCTAssertEqual(links.displayPath("/tmp/x"), "/tmp/x")
    }
}
