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

    // MARK: - hiddenCargoTargets

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rust-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return home
    }

    private func makeFolder(_ relativePath: String, in home: URL, tag: String? = nil, rustcInfo: Bool = false) throws {
        let folder = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let tag { try Data(tag.utf8).write(to: folder.appendingPathComponent("CACHEDIR.TAG")) }
        if rustcInfo { try Data("{}".utf8).write(to: folder.appendingPathComponent(".rustc_info.json")) }
    }

    private let cargoTag = "Signature: 8a477f597d28d172789f06886806bc55\n# This file is a cache directory tag created by cargo.\n"

    /// O caso real: `CARGO_TARGET_DIR` de instalador, com nome livre e sem `Cargo.toml`.
    func testFindsCargoTargetsInHiddenHomeFolders() throws {
        let home = try makeHome()
        try makeFolder(".vintagelightbox/target-gpui", in: home, tag: cargoTag, rustcInfo: true)
        try makeFolder(".vintagelightbox/fonte-gpui", in: home)
        try makeFolder(".direto", in: home, tag: cargoTag, rustcInfo: true)

        let found = RustTargetsCleaningService.hiddenCargoTargets(inHome: home.path)

        XCTAssertEqual(
            Set(found.map(\.displayName)),
            [".vintagelightbox/target-gpui", ".direto"]
        )
    }

    func testIgnoresWhatIsNotACargoTargetInHiddenFolders() throws {
        let home = try makeHome()
        // Tem a tag do cargo, mas é o cache de registry (categoria Cargo/Rust).
        try makeFolder(".cargo/registry", in: home, tag: cargoTag)
        // Tag de outra ferramenta.
        try makeFolder(".gradle/daemon", in: home, tag: "Signature: 8a477f597d28d172789f06886806bc55\n", rustcInfo: true)
        // Já está na Lixeira.
        try makeFolder(".Trash/target", in: home, tag: cargoTag, rustcInfo: true)
        // Pasta visível: não é o que esta busca rasa cobre.
        try makeFolder("Documentos/target", in: home, tag: cargoTag, rustcInfo: true)
        // Fundo demais.
        try makeFolder(".app/a/target", in: home, tag: cargoTag, rustcInfo: true)

        XCTAssertTrue(RustTargetsCleaningService.hiddenCargoTargets(inHome: home.path).isEmpty)
    }

    func testDoesNotFollowSymlinksOutOfHiddenFolders() throws {
        let home = try makeHome()
        let elsewhere = try makeHome()
        try makeFolder("target", in: elsewhere, tag: cargoTag, rustcInfo: true)
        try makeFolder(".app", in: home)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent(".app/target"),
            withDestinationURL: elsewhere.appendingPathComponent("target")
        )

        XCTAssertTrue(RustTargetsCleaningService.hiddenCargoTargets(inHome: home.path).isEmpty)
    }

    // MARK: - isBuildInProgress

    /// `cargo check` recente segura só o `.cargo-build-lock`.
    func testBuildLockCountsAsBuildInProgress() throws {
        let home = try makeHome()
        try makeFolder("target/instalador", in: home)
        let target = home.appendingPathComponent("target")
        let lock = target.appendingPathComponent("instalador/.cargo-build-lock")
        try Data().write(to: lock)

        let service = RustTargetsCleaningService(useTrash: false)
        XCTAssertFalse(service.isBuildInProgress(targetPath: target.path))

        let descriptor = open(lock.path, O_RDONLY)
        defer { close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX), 0)
        XCTAssertTrue(service.isBuildInProgress(targetPath: target.path))
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
