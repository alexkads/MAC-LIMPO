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

    // MARK: - trashItem

    func testTrashItemMovesFileToTrashAndReportsSuccess() throws {
        let fm = FileManager.default
        let name = "maclimpo-trash-\(UUID().uuidString).bin"
        let src = fm.temporaryDirectory.appendingPathComponent(name)
        try Data(repeating: 1, count: 1024).write(to: src)

        let ok = FileSystemHelper.shared.trashItem(atPath: src.path)
        XCTAssertTrue(ok, "deve conseguir mover para a Lixeira")
        XCTAssertFalse(fm.fileExists(atPath: src.path), "arquivo não deve mais estar no path original")

        // Limpa o item da Lixeira (nome único evita colisão/renomeação).
        let trashed = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash/\(name)")
        try? fm.removeItem(at: trashed)
    }

    /// Regressão: a versão antiga interpolava o path em `du -sk '...'`, quebrando
    /// em paths com aspa simples ou espaço. Agora o path vai como argumento.
    func testSizeOfDirectoryHandlesPathWithQuotesAndSpaces() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("maclimpo it's a \"test\" \(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try Data(repeating: 0, count: 120_000).write(to: dir.appendingPathComponent("f.bin"))

        XCTAssertGreaterThan(FileSystemHelper.shared.sizeOfDirectory(atPath: dir.path), 0)
    }

    func testSizeOfDirectoryOnMissingPathIsZero() {
        XCTAssertEqual(FileSystemHelper.shared.sizeOfDirectory(atPath: "/nonexistent/maclimpo/\(UUID().uuidString)"), 0)
    }

    // MARK: - parseDuBatch / sizesOfDirectories

    func testParseDuBatchParsesEveryLineAndKeepsSpacesInPath() {
        let output = "4\t/tmp/a\n1024\t/tmp/with space/dir\n"
        let parsed = FileSystemHelper.parseDuBatch(output)
        XCTAssertEqual(parsed.map(\.path), ["/tmp/a", "/tmp/with space/dir"])
        XCTAssertEqual(parsed.map(\.bytes), [4 * 1024, 1024 * 1024])
    }

    func testParseDuBatchIgnoresMalformedLines() {
        let output = "du: /x: Permission denied\nabc\t/tmp/a\n8\t\n16\t/tmp/b"
        let parsed = FileSystemHelper.parseDuBatch(output)
        XCTAssertEqual(parsed.map(\.path), ["/tmp/b"])
        XCTAssertEqual(parsed.first?.bytes, 16 * 1024)
    }

    func testSizesOfDirectoriesMeasuresAcrossBatchesAndSkipsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("du-batch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let dirs = ["one", "two", "with space"].map { root.appendingPathComponent($0) }
        for dir in dirs {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: 64 * 1024).write(to: dir.appendingPathComponent("blob"))
        }
        let missing = root.appendingPathComponent("missing").path

        // batchSize 2 força mais de uma invocação do `du`.
        let sizes = FileSystemHelper.shared.sizesOfDirectories(
            atPaths: dirs.map(\.path) + [missing],
            batchSize: 2
        )

        XCTAssertEqual(Set(sizes.keys), Set(dirs.map(\.path)))
        for dir in dirs {
            XCTAssertGreaterThanOrEqual(sizes[dir.path] ?? 0, 64 * 1024)
        }
        XCTAssertNil(sizes[missing])
    }

    func testSizesOfDirectoriesEmptyInput() {
        XCTAssertTrue(FileSystemHelper.shared.sizesOfDirectories(atPaths: []).isEmpty)
    }
}
