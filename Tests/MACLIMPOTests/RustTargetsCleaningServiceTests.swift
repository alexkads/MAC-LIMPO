import XCTest
@testable import MAC_LIMPO

final class RustTargetsCleaningServiceTests: XCTestCase {
    // MARK: - hostMountPoints

    /// Caso real que falhava: projeto em bind mount e volume nomeado em
    /// `/app/target` — a pasta `backend/target` do Mac é o ponto de montagem.
    func testVolumeOverBindMountMapsToHostTargetDir() {
        let output = """
        /recordarfotos-dev-api-1|bind|/Users/me/Projects/shop/backend|/app
        /recordarfotos-dev-api-1|volume|/var/lib/docker/volumes/dev_cargo-target/_data|/app/target
        /recordarfotos-dev-api-1|volume|/var/lib/docker/volumes/dev_uploads/_data|/data/uploads
        """
        let mounts = RustTargetsCleaningService.hostMountPoints(fromInspect: output)
        XCTAssertEqual(mounts, ["/Users/me/Projects/shop/backend/target": "recordarfotos-dev-api-1"])
    }

    func testHostMntPrefixIsStripped() {
        let output = """
        /web|bind|/host_mnt/Users/me/Projects/shop/frontend|/app
        /web|volume|/var/lib/docker/volumes/next/_data|/app/.next
        """
        let mounts = RustTargetsCleaningService.hostMountPoints(fromInspect: output)
        XCTAssertEqual(mounts["/Users/me/Projects/shop/frontend/.next"], "web")
    }

    func testMountsFromOtherContainersAndUnrelatedPathsAreIgnored() {
        let output = """
        /a|bind|/Users/me/proj|/app
        /b|volume|/var/lib/docker/volumes/x/_data|/app/target
        /a|volume|/var/lib/docker/volumes/y/_data|/application
        garbage line
        """
        XCTAssertTrue(RustTargetsCleaningService.hostMountPoints(fromInspect: output).isEmpty)
    }

    // MARK: - emptyDirectory

    func testEmptyDirectoryKeepsFolderAndRemovesEverythingInside() throws {
        let fileManager = FileManager.default
        let target = fileManager.temporaryDirectory
            .appendingPathComponent("rust-target-\(UUID().uuidString)")
            .appendingPathComponent("target")
        try fileManager.createDirectory(at: target.appendingPathComponent("debug/deps"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: target.appendingPathComponent("debug/deps/libfoo.rlib"))
        try Data("{}".utf8).write(to: target.appendingPathComponent(".rustc_info.json"))
        try Data("Signature".utf8).write(to: target.appendingPathComponent("CACHEDIR.TAG"))
        defer { try? fileManager.removeItem(at: target.deletingLastPathComponent()) }

        let failures = RustTargetsCleaningService(useTrash: false).emptyDirectory(atPath: target.path)

        XCTAssertTrue(failures.isEmpty)
        XCTAssertTrue(fileManager.fileExists(atPath: target.path), "a pasta target/ deve continuar existindo")
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: target.path), [], "inclusive arquivos ocultos")
    }
}
