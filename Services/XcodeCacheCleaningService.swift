import Foundation

class XcodeCacheCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .xcodeCache
    
    private let xcodePaths = [
        "~/Library/Developer/Xcode/DerivedData",
        "~/Library/Developer/Xcode/Archives",
        "~/Library/Developer/Xcode/iOS DeviceSupport",
        "~/Library/Developer/Xcode/watchOS DeviceSupport",
        "~/Library/Developer/Xcode/tvOS DeviceSupport",
        "~/Library/Caches/com.apple.dt.Xcode",
        "~/Library/Developer/CoreSimulator/Caches"
    ]
    
    func scan() async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for path in xcodePaths {
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
        
        for path in xcodePaths {
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
            success: errors.count < filesRemoved / 2
        )
    }
}
