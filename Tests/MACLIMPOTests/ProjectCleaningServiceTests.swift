import XCTest
@testable import MAC_LIMPO

/// Que pastas de projeto contam como artefato de build.
final class ProjectCleaningServiceTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("maclimpo-projects-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func make(_ relPath: String) throws {
        let url = root.appendingPathComponent(relPath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    /// "pai/pasta" de cada artefato encontrado.
    private func artifacts() -> [String] {
        ProjectCleaningService.artifactFolders(under: root.path).map { path in
            let url = URL(fileURLWithPath: path)
            return "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)"
        }
    }

    func testOnlyFoldersProvenByTheirEcosystemMarker() throws {
        try make("web/package.json")
        try make("web/node_modules/left-pad/index.js")
        try make("web/node_modules/left-pad/node_modules/inner/index.js")
        // electron-builder: recursos versionados em build/; libs que versionam dist/
        try make("web/build/icon.icns")
        try make("web/dist/bundle.js")
        try make("android/app/build.gradle")
        try make("android/app/build/outputs/app.apk")
        try make("mobile/pubspec.yaml")
        try make("mobile/build/ios/Runner.app.zip")
        try make("py/pyproject.toml")
        try make("py/dist/pkg-1.0.whl")
        try make("loose/node_modules/x/index.js")
        try make("cmake/build/CMakeCache.txt")

        XCTAssertEqual(
            artifacts().sorted(),
            ["app/build", "mobile/build", "py/dist", "web/node_modules"]
        )
    }
}
