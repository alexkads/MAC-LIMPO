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

    // MARK: - du

    func testParseSizesConvertsKilobytesAndKeepsSpacesInPaths() {
        let sizes = DuOutput.parseSizes("10\t/a\n2048\t/a/My Folder\ngarbage\n")
        XCTAssertEqual(sizes["/a"], 10 * 1024)
        XCTAssertEqual(sizes["/a/My Folder"], 2048 * 1024)
        XCTAssertEqual(sizes.count, 2)
    }

    func testParseUnreadableKeepsOnlyPermissionErrors() {
        let stderr = """
        du: /a/Mail: Operation not permitted
        du: /a/b: Permission denied
        du: /a/c: No such file or directory
        """
        XCTAssertEqual(DuOutput.parseUnreadable(stderr), ["/a/Mail", "/a/b"])
    }

    func testBuildTreeAddsLooseFilesMarksPartialAndStopsAtDepth() throws {
        let sizes: [String: Int64] = [
            "/r": 100, "/r/a": 60, "/r/a/x": 50, "/r/b": 30
        ]
        let tree = try XCTUnwrap(DuOutput.buildTree(
            root: "/r", sizes: sizes, unreadable: ["/r/a/x"], maxDepth: 1, displayPath: { $0 }
        ))
        XCTAssertEqual(tree.size, 100)
        let children = try XCTUnwrap(tree.children)
        XCTAssertEqual(children.map(\.name), ["a", "b", "Files in this folder"], "ordenado por tamanho")
        XCTAssertEqual(children.last?.size, 10, "100 - 60 - 30 = arquivos soltos")
        XCTAssertNil(children.first?.children, "além da profundidade: carrega sob demanda")
        XCTAssertTrue(tree.isPartial)
        XCTAssertTrue(children[0].isPartial, "ancestral de pasta ilegível")
        XCTAssertFalse(children[1].isPartial)
    }

    func testRemovingChildShrinksEveryAncestor() throws {
        let sizes: [String: Int64] = ["/r": 100, "/r/a": 60, "/r/a/x": 50]
        let tree = try XCTUnwrap(DuOutput.buildTree(
            root: "/r", sizes: sizes, unreadable: [], maxDepth: 3, displayPath: { $0 }
        ))
        let a = try XCTUnwrap(tree.children?.first { $0.name == "a" })
        let x = try XCTUnwrap(a.children?.first { $0.name == "x" })
        a.remove(x)
        XCTAssertEqual(a.size, 10)
        XCTAssertEqual(tree.size, 50)
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

    // MARK: - Dicas e Lixeira

    func testHintsCoverDockerAndServiceTargets() {
        let home = "/Users/me"
        XCTAssertEqual(
            XRayHints.hint(forDisplayPath: "/Users/me/Library/Containers/com.docker.docker", home: home)?.category,
            .docker
        )
        XCTAssertNil(XRayHints.hint(forDisplayPath: "/Users/me/random", home: home))
    }

    func testCanTrashOnlyInsideHomeAndNeverItsBaseFolders() {
        let home = "/Users/me"
        XCTAssertTrue(XRayHints.canTrash(displayPath: "/Users/me/.vintagelightbox", home: home))
        XCTAssertTrue(XRayHints.canTrash(displayPath: "/Users/me/Downloads/big.pkg", home: home))
        XCTAssertTrue(XRayHints.canTrash(displayPath: "/Users/me/Library/Caches/com.x", home: home))
        XCTAssertFalse(XRayHints.canTrash(displayPath: "/Users/me/Library", home: home))
        XCTAssertFalse(XRayHints.canTrash(displayPath: "/Users/me/Library/Caches", home: home))
        XCTAssertFalse(XRayHints.canTrash(displayPath: "/Users/me/Documents", home: home))
        XCTAssertFalse(XRayHints.canTrash(displayPath: "/Users/me", home: home))
        XCTAssertFalse(XRayHints.canTrash(displayPath: "/Applications/Xcode.app", home: home))
        XCTAssertFalse(XRayHints.canTrash(displayPath: "/Users/meow/x", home: home))
    }

    // MARK: - Maiores arquivos

    func testLargestFilesFindsDeepFilesInSizeOrder() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("xray-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let deep = root.appendingPathComponent("a/b/c")
        try fileManager.createDirectory(at: deep, withIntermediateDirectories: true)
        try Data(count: 300_000).write(to: deep.appendingPathComponent("big.bin"))
        try Data(count: 100_000).write(to: root.appendingPathComponent("a/medium.bin"))
        try Data(count: 10).write(to: root.appendingPathComponent(".hidden"))

        let found = DiskXRayService.shared.largestFiles(under: root.path, limit: 2, isCancelled: { false })
        XCTAssertEqual(found.map(\.name), ["big.bin", "medium.bin"])
        XCTAssertGreaterThanOrEqual(found[0].size, 300_000, "espaço alocado, não lógico")
    }
}
