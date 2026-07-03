import XCTest
@testable import MAC_LIMPO

/// Testes de caracterização das funções puras do FileSystemHelper.
/// Fixam o comportamento atual antes do refactor (Fase 0 do REFACTOR_PLAN).
final class FileSystemHelperTests: XCTestCase {
    // MARK: - parseDuKilobytes

    func testParseDuKilobytesSimple() {
        // `du -sk` reporta em KB; helper deve devolver bytes.
        XCTAssertEqual(FileSystemHelper.parseDuKilobytes("1024"), 1024 * 1024)
        XCTAssertEqual(FileSystemHelper.parseDuKilobytes("0"), 0)
    }

    func testParseDuKilobytesWithWhitespaceAndNewline() {
        XCTAssertEqual(FileSystemHelper.parseDuKilobytes("  512\n"), 512 * 1024)
        XCTAssertEqual(FileSystemHelper.parseDuKilobytes("512\t/some/path\n"), 512 * 1024)
    }

    func testParseDuKilobytesInvalidReturnsNil() {
        XCTAssertNil(FileSystemHelper.parseDuKilobytes(""))
        XCTAssertNil(FileSystemHelper.parseDuKilobytes("du: No such file"))
    }

    // MARK: - expandPath

    func testExpandPathResolvesTilde() {
        let expanded = FileSystemHelper.shared.expandPath("~/Library/Caches")
        XCTAssertFalse(expanded.hasPrefix("~"))
        XCTAssertTrue(expanded.hasSuffix("/Library/Caches"))
        XCTAssertTrue(expanded.hasPrefix("/"))
    }

    func testExpandPathLeavesAbsoluteUnchanged() {
        XCTAssertEqual(FileSystemHelper.shared.expandPath("/tmp/x"), "/tmp/x")
    }

    // MARK: - formatBytes

    func testFormatBytesProducesHumanReadable() {
        // ByteCountFormatter usa unidades; validamos que não é vazio e reflete a ordem de grandeza.
        let formatted = FileSystemHelper.shared.formatBytes(0)
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertTrue(FileSystemHelper.shared.formatBytes(5_000_000).contains("MB"))
    }

    // MARK: - sizeOfDirectory (integração leve com tmp real)

    func testSizeOfDirectoryOnRealTempDir() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("maclimpo-test-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let data = Data(repeating: 0, count: 200_000) // ~200 KB
        try data.write(to: dir.appendingPathComponent("blob.bin"))

        let size = FileSystemHelper.shared.sizeOfDirectory(atPath: dir.path)
        XCTAssertGreaterThan(size, 0, "diretório com conteúdo deve reportar tamanho > 0")
    }

    func testSizeOfDirectoryOnMissingPathIsZero() {
        XCTAssertEqual(FileSystemHelper.shared.sizeOfDirectory(atPath: "/nonexistent/maclimpo/\(UUID().uuidString)"), 0)
    }
}
