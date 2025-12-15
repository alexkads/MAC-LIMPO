import Foundation

class DownloadsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .downloads
    
    private let downloadsPath = "~/Downloads"
    private let daysOld = 30
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        let expandedPath = fileHelper.expandPath(downloadsPath)
        let contents = fileHelper.contentsOfDirectory(atPath: expandedPath)
        
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -daysOld, to: Date()) ?? Date()
        
        for item in contents {
            let itemPath = (expandedPath as NSString).appendingPathComponent(item)
            
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: itemPath)
                if let modificationDate = attributes[.modificationDate] as? Date {
                    if modificationDate < cutoffDate {
                        let size = fileHelper.sizeOfDirectory(atPath: itemPath)
                        totalSize += size
                        items.append(item)
                    }
                }
            } catch {
                continue
            }
        }
        
        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: items.count,
            items: items.prefix(10).map { "\($0)" }
        )
    }
    
    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []
        
        let expandedPath = fileHelper.expandPath(downloadsPath)
        let contents = fileHelper.contentsOfDirectory(atPath: expandedPath)
        
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -daysOld, to: Date()) ?? Date()
        
        for item in contents {
            let itemPath = (expandedPath as NSString).appendingPathComponent(item)
            
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: itemPath)
                if let modificationDate = attributes[.modificationDate] as? Date {
                    if modificationDate < cutoffDate {
                        let size = fileHelper.sizeOfDirectory(atPath: itemPath)
                        try fileHelper.removeItem(atPath: itemPath)
                        bytesRemoved += size
                        filesRemoved += 1
                    }
                }
            } catch {
                errors.append("Failed to remove \(item): \(error.localizedDescription)")
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
