import Foundation

/// Service to clean development project artifacts.
///
/// Uma pasta só entra com o marcador do ecossistema ao lado, que prova que ela
/// é saída de ferramenta: `node_modules` com `package.json`, `build` de Gradle
/// ou Flutter, `dist` de pacote Python. `build`/`dist` de projeto JavaScript
/// ficam — o electron-builder guarda ícones e entitlements versionados em
/// `build/`, e há bibliotecas que versionam o `dist/`. Tudo vai para a Lixeira.
/// Rust `target/` dirs live in `RustTargetsCleaningService` — they dwarf everything
/// else here, so they get their own category instead of hiding inside this total.
class ProjectCleaningService: BaseCleaningService, CleaningService, @unchecked Sendable {
    let category: CleaningCategory = .development

    /// Configurable paths to scan
    private let projectRoot = "~/Projects"

    /// Pasta de artefato → arquivos que, ao lado dela, provam que é saída de build.
    static let artifactMarkers: [String: Set<String>] = [
        "node_modules": ["package.json"],
        "build": ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "pubspec.yaml"],
        "dist": ["pyproject.toml", "setup.py", "setup.cfg"]
    ]

    /// Only suggest big folders (> 50 MB) to avoid noise
    static let minimumSize: Int64 = 50 * 1024 * 1024

    /// Pastas de artefato sob `root`, sem medir. Não desce nelas nem em pastas
    /// ocultas ou pacotes.
    static func artifactFolders(under root: String) -> [String] {
        let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var folders: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard let markers = artifactMarkers[url.lastPathComponent],
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }
            let siblings = FileSystemHelper.shared.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            guard !markers.isDisjoint(with: siblings) else { continue }
            folders.append(url.path)
            enumerator?.skipDescendants()
        }
        return folders.sorted()
    }

    /// O que a limpeza leva: as pastas de artefato acima do tamanho mínimo.
    private func candidates(progress: (@Sendable (String) -> Void)? = nil) async -> [(path: String, size: Int64)] {
        let folders = Self.artifactFolders(under: fileHelper.expandPath(projectRoot))
        progress?(String(localized: "Measuring \(folders.count) paths…"))
        let sizes = await fileHelper.sizesOfDirectoriesAsync(atPaths: folders)
        return folders.compactMap { path in
            let size = sizes[path] ?? 0
            return size > Self.minimumSize ? (path, size) : nil
        }
    }

    func scan(progress: (@Sendable (String) -> Void)?) async -> ScanResult {
        Logger.shared.log("Scanning projects for build artifacts...", level: .info)

        let expandedRoot = fileHelper.expandPath(projectRoot)
        let found = await candidates(progress: progress)
        let items = found.map { "\($0.path.replacingOccurrences(of: expandedRoot, with: "")) (\(fileHelper.formatBytes($0.size)))" }

        return ScanResult(
            category: category,
            estimatedSize: found.reduce(0) { $0 + $1.size },
            itemCount: items.count,
            items: items
        )
    }

    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []

        for (path, size) in await candidates() {
            if fileHelper.trashItem(atPath: path) {
                bytesRemoved += size
                filesRemoved += 1
                Logger.shared.log("Cleaned project artifact: \(path)", level: .info)
            } else {
                errors.append(String(localized: "Could not move \((path as NSString).lastPathComponent) to the Trash."))
            }
        }

        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: Date().timeIntervalSince(startTime),
            success: errors.isEmpty
        )
    }
}
