import Foundation

/// Service to clean Podcasts downloads and caches
class PodcastsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .podcasts
    
    private let podcastPaths = [
        "~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Documents", // Downloaded episodes
        "~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache",
        "~/Library/Containers/com.apple.podcasts/Data/Library/Caches",
        "~/Library/Caches/com.apple.podcasts"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for path in podcastPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    totalSize += size
                    let name = path.contains("Documents") ? "Downloaded Episodes" : "Cache"
                    items.append("\(name): \(fileHelper.formatBytes(size))")
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
        let errors: [String] = []
        
        for path in podcastPaths {
            let expandedPath = fileHelper.expandPath(path)
            
            // Special handling for Downloads to verify if we should delete
            // For now, valid implementation is to clean contents
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                let contents = fileHelper.contentsOfDirectory(atPath: expandedPath)
                
                for item in contents {
                    let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                    do {
                        try fileHelper.removeItem(atPath: itemPath)
                        filesRemoved += 1
                    } catch {}
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
