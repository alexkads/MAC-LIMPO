import Foundation

/// Service to clean Go programming language caches
/// Covers Go module cache, build cache, and gopls language server cache
class GoCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .goCache
    
    private let goModCachePaths = [
        "~/go/pkg/mod/cache"
    ]
    
    private let goBuildCachePaths = [
        "~/Library/Caches/go-build"
    ]
    
    private let goToolsCachePaths = [
        "~/Library/Caches/gopls"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        logger.log("Iniciando escaneamento de caches Go", level: .info)
        
        // Go module download cache
        progress?("Scanning Go module cache...")
        var modCacheSize: Int64 = 0
        for path in goModCachePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                modCacheSize += size
            }
        }
        if modCacheSize > 0 {
            totalSize += modCacheSize
            items.append("Go module cache: \(fileHelper.formatBytes(modCacheSize))")
            logger.log("Go module cache: \(fileHelper.formatBytes(modCacheSize))", level: .debug)
        }
        
        // Go build cache
        progress?("Scanning Go build cache...")
        var buildCacheSize: Int64 = 0
        for path in goBuildCachePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                buildCacheSize += size
            }
        }
        if buildCacheSize > 0 {
            totalSize += buildCacheSize
            items.append("Go build cache: \(fileHelper.formatBytes(buildCacheSize))")
            logger.log("Go build cache: \(fileHelper.formatBytes(buildCacheSize))", level: .debug)
        }
        
        // gopls language server cache
        progress?("Scanning gopls cache...")
        var goplsSize: Int64 = 0
        for path in goToolsCachePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                goplsSize += size
            }
        }
        if goplsSize > 0 {
            totalSize += goplsSize
            items.append("gopls language server: \(fileHelper.formatBytes(goplsSize))")
            logger.log("gopls cache: \(fileHelper.formatBytes(goplsSize))", level: .debug)
        }
        
        logger.log("Escaneamento Go concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        
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
        
        logger.log("Iniciando limpeza de caches Go", level: .info)
        
        let allPaths = goModCachePaths + goBuildCachePaths + goToolsCachePaths
        
        for path in allPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
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
                    logger.log("Limpo Go cache em \(path): \(fileHelper.formatBytes(size))", level: .debug)
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        logger.log("Limpeza Go concluída: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)
        
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
