import XCTest
@testable import MAC_LIMPO

final class DiskScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("scan-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try Data(count: 200_000).write(to: root.appendingPathComponent("a/b/movie.MP4"))
        try Data(count: 50_000).write(to: root.appendingPathComponent("a/.zshrc"))
        try Data(count: 10).write(to: root.appendingPathComponent("README"))
        try fm.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000_000_000)],
            ofItemAtPath: root.appendingPathComponent("a/b/movie.MP4").path
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func scan() throws -> DiskScanIndex {
        try XCTUnwrap(DiskScanner.scan(root: root.path, isCancelled: { false }, progress: { _ in }))
    }

    private func item(_ index: DiskScanIndex, _ relative: String) -> Int32? {
        (0 ..< Int32(index.count)).first { index.path($0) == root.appendingPathComponent(relative).path }
    }

    func testCountsSizesAndSubtreeRanges() throws {
        let index = try scan()
        XCTAssertEqual(index.count, 7, "raiz, a, b, empty e 3 arquivos")
        XCTAssertEqual(index.fileCount[0], 3)
        XCTAssertEqual(index.folderCount[0], 3, "a, a/b e empty")

        let a = try XCTUnwrap(item(index, "a"))
        let movie = try XCTUnwrap(item(index, "a/b/movie.MP4"))
        XCTAssertEqual(index.fileCount[Int(a)], 2)
        XCTAssertEqual(index.folderCount[Int(a)], 1)
        XCTAssertTrue(index.isAncestor(a, of: movie), "subárvore contígua em pré-ordem")
        XCTAssertGreaterThanOrEqual(index.physical[Int(movie)], 200_000)
        XCTAssertGreaterThanOrEqual(index.physical[0], index.physical[Int(a)])
        XCTAssertEqual(index.logical[Int(a)], 250_000)
    }

    func testExtensionsFollowWinDirStatRule() throws {
        let index = try scan()
        // CItem::GetExtension: do último ".", minúsculo; "" sem ponto; ".zshrc" é ".zshrc".
        XCTAssertEqual(index.extensionName(try XCTUnwrap(item(index, "a/b/movie.MP4"))), ".mp4")
        XCTAssertEqual(index.extensionName(try XCTUnwrap(item(index, "a/.zshrc"))), ".zshrc")
        XCTAssertEqual(index.extensionName(try XCTUnwrap(item(index, "README"))), "")
        XCTAssertNil(index.extensionName(try XCTUnwrap(item(index, "a"))), "pastas não têm extensão")
        let mp4 = try XCTUnwrap(index.extensions.firstIndex(of: ".mp4"))
        XCTAssertEqual(index.extensionLogical[mp4], 200_000)
        XCTAssertEqual(index.extensionFiles[mp4], 1)
    }

    func testFolderLastChangeIsMaxOfSubtree() throws {
        let index = try scan()
        let a = try XCTUnwrap(item(index, "a"))
        XCTAssertEqual(index.modified[Int(a)], 2_000_000_000)
        XCTAssertEqual(index.modified[0], 2_000_000_000)
    }

    func testRemoveUpdatesAncestorsAndExtensions() throws {
        let index = try scan()
        let movie = try XCTUnwrap(item(index, "a/b/movie.MP4"))
        let a = try XCTUnwrap(item(index, "a"))
        let rootLogical = index.logical[0]
        index.remove(movie)
        XCTAssertEqual(index.logical[0], rootLogical - 200_000)
        XCTAssertEqual(index.fileCount[Int(a)], 1)
        let mp4 = try XCTUnwrap(index.extensions.firstIndex(of: ".mp4"))
        XCTAssertEqual(index.extensionFiles[mp4], 0)
        XCTAssertFalse(index.children(try XCTUnwrap(item(index, "a/b"))).contains(movie))
    }

    func testLargestFilesByLogicalSize() throws {
        let index = try scan()
        let top = index.largestFiles(in: 0, limit: 2, logicalSize: true)
        XCTAssertEqual(top.map { index.name($0) }, ["movie.MP4", ".zshrc"])
    }
}

final class WinDirStatFormatTests: XCTestCase {
    private var sep: String { WinDirStatFormat.decimalSeparator }

    func testBytesUsesBinaryUnitsAndThresholds() {
        XCTAssertEqual(WinDirStatFormat.bytes(0), "0 bytes")
        XCTAssertEqual(WinDirStatFormat.bytes(1023), "1023 bytes")
        XCTAssertEqual(WinDirStatFormat.bytes(1024), "1\(sep)00 KiB")
        XCTAssertEqual(WinDirStatFormat.bytes(1536), "1\(sep)50 KiB")
        // Limiar do MiB é Mi − Ki/2: logo abaixo ainda é KiB.
        XCTAssertEqual(WinDirStatFormat.bytes(1024 * 1024 - 513), "1023\(sep)50 KiB")
        XCTAssertEqual(WinDirStatFormat.bytes(1024 * 1024 - 512), "1\(sep)00 MiB")
        XCTAssertEqual(WinDirStatFormat.bytes(Int64(48.7 * 1024 * 1024 * 1024)), "48\(sep)70 GiB")
    }

    func testDoubleRoundsHalfAwayFromZeroWithTwoDigits() {
        XCTAssertEqual(WinDirStatFormat.double(0), "0\(sep)00")
        XCTAssertEqual(WinDirStatFormat.double(12.346), "12\(sep)35")
        XCTAssertEqual(WinDirStatFormat.double(99.999), "100\(sep)00")
        XCTAssertEqual(WinDirStatFormat.percent(0.5), "50\(sep)00%")
    }

    func testFileTimeHasTwoSpacesBetweenDateAndTime() {
        let text = WinDirStatFormat.fileTime(2_000_000_000)
        XCTAssertTrue(text.contains("  "))
        XCTAssertEqual(WinDirStatFormat.fileTime(0), "")
    }
}
