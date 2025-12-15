import Foundation

class SlackCacheCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .slackCache
    
    private let slackPaths = [
        "~/Library/Application Support/Slack/Cache",
        "~/Library/Application Support/Slack/Code Cache",
        "~/Library/Application Support/Slack/Service Worker/CacheStorage",
        "~/Library/Application Support/Slack/Local Storage",
        "~/Library/Caches/com.tinyspeck.slackmacgap",
        "~/Library/Caches/com.tinyspeck.slackmacgap.ShipIt"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for path in slackPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    totalSize += size
                    let pathName = (path as NSString).lastPathComponent
                    items.append("\(pathName): \(fileHelper.formatBytes(size))")
                }
            }
        }
        
        if items.isEmpty {
            items.append("Slack not installed or no cache")
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
        
        for path in slackPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                let contents = fileHelper.contentsOfDirectory(atPath: expandedPath)
                
                for item in contents {
                    let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                    do {
                        try fileHelper.removeItem(atPath: itemPath)
                        filesRemoved += 1
                    } catch {
                        errors.append("Failed to remove \(item): \(error.localizedDescription)")
                    }
                }
                
                bytesRemoved += size
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
