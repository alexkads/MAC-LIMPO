import Foundation

class SpotifyCacheCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .spotifyCache
    
    private let spotifyPaths = [
        "~/Library/Caches/com.spotify.client",
        "~/Library/Caches/com.spotify.client.helper",
        "~/Library/Application Support/Spotify/PersistentCache",
        "~/Library/Application Support/Spotify/Users/*-user/local-files.bnk"
    ]
    
    private func resolvePaths(_ path: String) -> [String] {
        let expanded = fileHelper.expandPath(path)
        
        if path.contains("*") {
            let components = expanded.components(separatedBy: "/*")
            if components.count >= 2 {
                let baseFolder = components[0]
                let remainingPath = components[1]
                
                let contents = fileHelper.contentsOfDirectory(atPath: baseFolder)
                var results: [String] = []
                
                for item in contents {
                    let itemPath = (baseFolder as NSString).appendingPathComponent(item)
                    let finalPath = (itemPath as NSString).appendingPathComponent(remainingPath)
                    if fileHelper.fileExists(atPath: finalPath) {
                        results.append(finalPath)
                    }
                }
                return results
            }
        }
        
        return [expanded]
    }
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for path in spotifyPaths {
            for resolvedPath in resolvePaths(path) {
                if fileHelper.fileExists(atPath: resolvedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: resolvedPath)
                    if size > 0 {
                        totalSize += size
                        let displayName = (resolvedPath as NSString).lastPathComponent
                        items.append("\(displayName): \(fileHelper.formatBytes(size))")
                    }
                }
            }
        }
        
        if items.isEmpty {
            items.append("Spotify not installed or no cache")
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
        
        for path in spotifyPaths {
            for resolvedPath in resolvePaths(path) {
                if fileHelper.fileExists(atPath: resolvedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: resolvedPath)
                    
                    do {
                        var isDirectory: ObjCBool = false
                        FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory)
                        
                        if isDirectory.boolValue {
                            let contents = fileHelper.contentsOfDirectory(atPath: resolvedPath)
                            for item in contents {
                                let itemPath = (resolvedPath as NSString).appendingPathComponent(item)
                                try fileHelper.removeItem(atPath: itemPath)
                                filesRemoved += 1
                            }
                        } else {
                            try fileHelper.removeItem(atPath: resolvedPath)
                            filesRemoved += 1
                        }
                        
                        bytesRemoved += size
                    } catch {
                        errors.append("Failed to clean cache: \(error.localizedDescription)")
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
            success: true
        )
    }
}
