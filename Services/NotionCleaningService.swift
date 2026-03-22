import Foundation

/// Service to clean Notion app caches
/// Covers asset cache, GPU cache, and other regenerable data
class NotionCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .notionCache
    
    // Safe to clean - these are all regenerable caches
    private let notionCachePaths = [
        "~/Library/Application Support/Notion/notionAssetCache-v2",
        "~/Library/Application Support/Notion/DawnCache",
        "~/Library/Application Support/Notion/GPUCache",
        "~/Library/Application Support/Notion/Code Code",
        "~/Library/Application Support/Notion/Cache",
        "~/Library/Caches/com.notion.id"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        logger.log("Iniciando escaneamento do Notion", level: .info)
        progress?("Scanning Notion cache...")
        
        let pathNames: [String: String] = [
            "notionAssetCache-v2": "Asset cache (images/icons)",
            "DawnCache": "GPU/Dawn cache",
            "GPUCache": "GPU cache",
            "Code Code": "Code cache",
            "Cache": "General cache"
        ]
        
        for path in notionCachePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    totalSize += size
                    let folderName = (expandedPath as NSString).lastPathComponent
                    let displayName = pathNames[folderName] ?? folderName
                    items.append("Notion \(displayName): \(fileHelper.formatBytes(size))")
                    logger.log("Notion \(folderName): \(fileHelper.formatBytes(size))", level: .debug)
                }
            }
        }
        
        logger.log("Escaneamento Notion concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        
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
        
        logger.log("Iniciando limpeza do Notion", level: .info)
        
        for path in notionCachePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                
                // Clean contents to preserve the folder structure
                let contents = fileHelper.contentsOfDirectory(atPath: expandedPath)
                var removed = false
                
                for item in contents {
                    let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                    do {
                        try fileHelper.removeItem(atPath: itemPath)
                        filesRemoved += 1
                        removed = true
                    } catch {
                        logger.log("Falha ao remover \(item): \(error.localizedDescription)", level: .error)
                    }
                }
                
                if removed {
                    bytesRemoved += size
                    let folderName = (expandedPath as NSString).lastPathComponent
                    logger.log("Limpo Notion \(folderName): \(fileHelper.formatBytes(size))", level: .debug)
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        logger.log("Limpeza Notion concluída: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)
        
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
