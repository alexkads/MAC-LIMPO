import Foundation

class AppCacheCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .appCache
    
    private let cachePaths = [
        ("Safari", "~/Library/Caches/com.apple.Safari"),
        ("Safari WebKit", "~/Library/Caches/com.apple.WebKit.WebContent"),
        ("Chrome", "~/Library/Caches/Google/Chrome"),
        ("Firefox", "~/Library/Caches/Firefox"),
        ("Spotify", "~/Library/Caches/com.spotify.client"),
        ("Mail", "~/Library/Mail/V10/MailData/Envelope Index"),
        ("Adobe", "~/Library/Caches/Adobe"),
        ("Adobe Apps", "~/Library/Caches/com.adobe.*")
    ]
    
    private func resolvePaths(_ path: String) -> [String] {
        let expanded = fileHelper.expandPath(path)
        
        if path.contains("*") {
            let folder = (expanded as NSString).deletingLastPathComponent
            let pattern = (expanded as NSString).lastPathComponent
            let prefix = pattern.replacingOccurrences(of: "*", with: "")
            
            let contents = fileHelper.contentsOfDirectory(atPath: folder)
            return contents
                .filter { $0.hasPrefix(prefix) }
                .map { (folder as NSString).appendingPathComponent($0) }
        } else {
            return [expanded]
        }
    }
    
    func scan() async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for (name, path) in cachePaths {
            for resolvedPath in resolvePaths(path) {
                if fileHelper.fileExists(atPath: resolvedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: resolvedPath)
                    if size > 0 {
                        totalSize += size
                        // Se for wildcard, usa o nome do diretório
                        let displayName = path.contains("*") ? (resolvedPath as NSString).lastPathComponent : name
                        items.append("\(displayName): \(fileHelper.formatBytes(size))")
                    }
                }
            }
        }
        
        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: items.count,
            items: items
        )
    }
    
    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []
        
        for (name, path) in cachePaths {
            for resolvedPath in resolvePaths(path) {
                if fileHelper.fileExists(atPath: resolvedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: resolvedPath)
                    
                    // Para caches de app, limpa conteúdo mas mantém diretório
                    let contents = fileHelper.contentsOfDirectory(atPath: resolvedPath)
                    for item in contents {
                        let itemPath = (resolvedPath as NSString).appendingPathComponent(item)
                        do {
                            try fileHelper.removeItem(atPath: itemPath)
                            filesRemoved += 1
                        } catch {
                            let displayName = path.contains("*") ? (resolvedPath as NSString).lastPathComponent : name
                            errors.append("Failed to clean \(displayName) cache: \(error.localizedDescription)")
                        }
                    }
                    
                    bytesRemoved += size
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        
        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: executionTime,
            success: errors.isEmpty
        )
    }
}
