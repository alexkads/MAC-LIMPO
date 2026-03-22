import Foundation

/// Service to clean pnpm package manager caches
/// Covers pnpm global store, dlx cache, and metadata caches
class PnpmCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .pnpm
    
    private let pnpmStorePaths = [
        "~/Library/pnpm/store"
    ]
    
    private let pnpmCachePaths = [
        "~/Library/Caches/pnpm/dlx",
        "~/Library/Caches/pnpm/metadata-full-v1.3",
        "~/Library/Caches/pnpm/metadata-v1.3",
        "~/Library/Caches/pnpm"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        logger.log("Iniciando escaneamento do pnpm", level: .info)
        
        // Scan pnpm cache (safe to clean - regenerable)
        progress?("Scanning pnpm cache...")
        var cacheSize: Int64 = 0
        for path in pnpmCachePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    cacheSize += size
                }
            }
        }
        if cacheSize > 0 {
            totalSize += cacheSize
            items.append("pnpm cache (dlx, metadata): \(fileHelper.formatBytes(cacheSize))")
            logger.log("pnpm cache: \(fileHelper.formatBytes(cacheSize))", level: .debug)
        }
        
        // Scan pnpm store (package store - safe to clean if packages can be re-downloaded)
        progress?("Scanning pnpm store...")
        var storeSize: Int64 = 0
        for path in pnpmStorePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    storeSize += size
                }
            }
        }
        if storeSize > 0 {
            totalSize += storeSize
            items.append("pnpm store (packages): \(fileHelper.formatBytes(storeSize))")
            logger.log("pnpm store: \(fileHelper.formatBytes(storeSize))", level: .debug)
        }
        
        logger.log("Escaneamento pnpm concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        
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
        
        logger.log("Iniciando limpeza do pnpm", level: .info)
        
        // Clean pnpm cache first (always safe)
        for path in pnpmCachePaths {
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
                        logger.log("Falha ao remover \(item): \(error.localizedDescription)", level: .error)
                    }
                }
                bytesRemoved += size
                logger.log("Limpo pnpm cache: \(fileHelper.formatBytes(size))", level: .debug)
            }
        }
        
        // Clean pnpm store (packages will be re-downloaded when needed)
        for path in pnpmStorePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                do {
                    try fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                    logger.log("Removido pnpm store: \(fileHelper.formatBytes(size))", level: .debug)
                } catch {
                    errors.append("Falha ao limpar pnpm store: \(error.localizedDescription)")
                    logger.log("Falha ao remover pnpm store: \(error.localizedDescription)", level: .error)
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        logger.log("Limpeza pnpm concluída: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)
        
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
