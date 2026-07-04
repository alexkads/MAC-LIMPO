import Foundation

/// Limpa caches de navegadores. Para browsers Chromium (Chrome, Edge, Brave, Arc)
/// os caches ficam **por profile** (`Default`, `Profile 1`, ...); antes só o
/// `Default` do Chrome era coberto e o `Service Worker` (frequentemente o maior)
/// era ignorado. Aqui enumeramos todos os profiles dinamicamente.
///
/// Só mexe em caches. NÃO apaga histórico/LocalStorage (dados do usuário).
final class BrowserCacheCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .browserCache

    /// Se `true` (produção), envia à Lixeira; testes usam `false`.
    private let useTrash: Bool

    init(useTrash: Bool = true) {
        self.useTrash = useTrash
    }

    /// Navegadores Chromium: (nome, user-data dir, cache de topo em ~/Library/Caches).
    private let chromiumBrowsers: [(name: String, userData: String, topCache: String)] = [
        ("Chrome", "~/Library/Application Support/Google/Chrome", "~/Library/Caches/Google/Chrome"),
        ("Edge", "~/Library/Application Support/Microsoft Edge", "~/Library/Caches/Microsoft Edge"),
        (
            "Brave",
            "~/Library/Application Support/BraveSoftware/Brave-Browser",
            "~/Library/Caches/BraveSoftware/Brave-Browser"
        ),
        (
            "Arc",
            "~/Library/Application Support/company.thebrowser.Browser",
            "~/Library/Caches/company.thebrowser.Browser"
        )
    ]

    /// Subpastas de cache (relativas ao profile) seguras para limpar.
    private let chromiumProfileCacheSubdirs = [
        "Cache",
        "Code Cache",
        "GPUCache",
        "DawnCache",
        "GrShaderCache",
        "Service Worker/CacheStorage",
        "Service Worker/ScriptCache"
    ]

    private let otherCaches: [(name: String, path: String)] = [
        ("Safari Cache", "~/Library/Caches/com.apple.Safari"),
        ("Safari WebKit", "~/Library/Caches/com.apple.WebKit.WebContent"),
        ("Firefox Cache", "~/Library/Caches/Firefox")
    ]

    private let firefoxProfilesRoot = "~/Library/Application Support/Firefox/Profiles"

    /// Dado o conteúdo de um user-data dir Chromium, devolve os nomes de profile
    /// (`Default` e `Profile N`). Função pura (testável).
    static func chromiumProfileNames(from contents: [String]) -> [String] {
        contents.filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted()
    }

    /// Coleta todos os diretórios de cache de navegador existentes (rótulo, path).
    private func collectCachePaths() -> [(name: String, path: String)] {
        var result: [(name: String, path: String)] = []

        for browser in chromiumBrowsers {
            let topCache = fileHelper.expandPath(browser.topCache)
            if fileHelper.fileExists(atPath: topCache) {
                result.append(("\(browser.name) cache", topCache))
            }

            let userData = fileHelper.expandPath(browser.userData)
            guard fileHelper.fileExists(atPath: userData) else { continue }

            let profiles = Self.chromiumProfileNames(from: fileHelper.contentsOfDirectory(atPath: userData))
            for profile in profiles {
                let profilePath = (userData as NSString).appendingPathComponent(profile)
                for sub in chromiumProfileCacheSubdirs {
                    let cachePath = (profilePath as NSString).appendingPathComponent(sub)
                    if fileHelper.fileExists(atPath: cachePath) {
                        result.append(("\(browser.name) \(profile)/\(sub)", cachePath))
                    }
                }
            }
        }

        for cache in otherCaches {
            let path = fileHelper.expandPath(cache.path)
            if fileHelper.fileExists(atPath: path) {
                result.append((cache.name, path))
            }
        }

        // Firefox: cache2 por profile.
        let ffRoot = fileHelper.expandPath(firefoxProfilesRoot)
        for profile in fileHelper.contentsOfDirectory(atPath: ffRoot) {
            let cache2 = (ffRoot as NSString).appendingPathComponent(profile) + "/cache2"
            if fileHelper.fileExists(atPath: cache2) {
                result.append(("Firefox \(profile)/cache2", cache2))
            }
        }

        return result
    }

    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []

        progress?("Scanning browser caches...")
        for entry in collectCachePaths() {
            let size = fileHelper.sizeOfDirectory(atPath: entry.path)
            if size > 0 {
                totalSize += size
                items.append("\(entry.name): \(fileHelper.formatBytes(size))")
            }
        }

        logger.log("Scan Browser Cache concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        return ScanResult(category: category, estimatedSize: totalSize, itemCount: items.count, items: items)
    }

    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []

        // Remove o conteúdo de cada diretório de cache (preserva a pasta que o
        // navegador espera existir), preferindo a Lixeira.
        for entry in collectCachePaths() {
            for child in fileHelper.contentsOfDirectory(atPath: entry.path) {
                let itemPath = (entry.path as NSString).appendingPathComponent(child)
                let size = fileHelper.sizeOfDirectory(atPath: itemPath)

                if useTrash, fileHelper.trashItem(atPath: itemPath) {
                    bytesRemoved += size
                    filesRemoved += 1
                    continue
                }

                do {
                    try fileHelper.removeItem(atPath: itemPath)
                    bytesRemoved += size
                    filesRemoved += 1
                } catch {
                    errors.append("Failed to clean \(entry.name): \(error.localizedDescription)")
                }
            }
        }

        logger.log("Limpeza Browser Cache: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)
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
