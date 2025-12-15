import Foundation

class BrowserCacheCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .browserCache
    
    private let browserCaches = [
        // Safari
        ("Safari Cache", "~/Library/Caches/com.apple.Safari"),
        ("Safari WebKit", "~/Library/Caches/com.apple.WebKit.WebContent"),
        ("Safari History", "~/Library/Safari/History.db"),
        ("Safari LocalStorage", "~/Library/Safari/LocalStorage"),
        
        // Chrome
        ("Chrome Cache", "~/Library/Caches/Google/Chrome"),
        ("Chrome Default Cache", "~/Library/Application Support/Google/Chrome/Default/Cache"),
        ("Chrome GPUCache", "~/Library/Application Support/Google/Chrome/Default/GPUCache"),
        ("Chrome Code Cache", "~/Library/Application Support/Google/Chrome/Default/Code Cache"),
        
        // Firefox
        ("Firefox Cache", "~/Library/Caches/Firefox"),
        ("Firefox Profiles Cache", "~/Library/Application Support/Firefox/Profiles/*/cache2"),
        
        // Edge
        ("Edge Cache", "~/Library/Caches/Microsoft Edge"),
        ("Edge Default Cache", "~/Library/Application Support/Microsoft Edge/Default/Cache"),
        
        // Brave
        ("Brave Cache", "~/Library/Caches/BraveSoftware/Brave-Browser"),
        ("Brave Default Cache", "~/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cache"),
        
        // Arc
        ("Arc Cache", "~/Library/Caches/company.thebrowser.Browser"),
    ]
    
    private func resolvePaths(_ path: String) -> [String] {
        let expanded = fileHelper.expandPath(path)
        
        if path.contains("*") {
            let folder = (expanded as NSString).deletingLastPathComponent
            let pattern = (expanded as NSString).lastPathComponent
            let prefix = pattern.replacingOccurrences(of: "/*", with: "")
            
            let contents = fileHelper.contentsOfDirectory(atPath: folder)
            var results: [String] = []
            
            for item in contents {
                if item.hasPrefix(prefix) || prefix.isEmpty {
                    let itemPath = (folder as NSString).appendingPathComponent(item)
                    let subPath = pattern.replacingOccurrences(of: "*/", with: "")
                    let finalPath = (itemPath as NSString).appendingPathComponent(subPath)
                    if fileHelper.fileExists(atPath: finalPath) {
                        results.append(finalPath)
                    }
                }
            }
            return results
        } else {
            return [expanded]
        }
    }
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for (name, path) in browserCaches {
            for resolvedPath in resolvePaths(path) {
                if fileHelper.fileExists(atPath: resolvedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: resolvedPath)
                    if size > 0 {
                        totalSize += size
                        items.append("\(name): \(fileHelper.formatBytes(size))")
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
        
        for (name, path) in browserCaches {
            for resolvedPath in resolvePaths(path) {
                if fileHelper.fileExists(atPath: resolvedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: resolvedPath)
                    
                    do {
                        // Para arquivos únicos (como History.db)
                        var isDirectory: ObjCBool = false
                        FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory)
                        
                        if isDirectory.boolValue {
                            // Para diretórios, limpa conteúdo
                            let contents = fileHelper.contentsOfDirectory(atPath: resolvedPath)
                            for item in contents {
                                let itemPath = (resolvedPath as NSString).appendingPathComponent(item)
                                try fileHelper.removeItem(atPath: itemPath)
                                filesRemoved += 1
                            }
                        } else {
                            // Para arquivos, remove o arquivo
                            try fileHelper.removeItem(atPath: resolvedPath)
                            filesRemoved += 1
                        }
                        
                        bytesRemoved += size
                    } catch {
                        errors.append("Failed to clean \(name): \(error.localizedDescription)")
                    }
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
            success: errors.count < filesRemoved / 2
        )
    }
}
