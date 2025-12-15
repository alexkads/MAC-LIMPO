import Foundation

class PlaywrightCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .playwright
    
    private let playwrightPaths = [
        "~/Library/Caches/ms-playwright",
        "~/Library/Caches/ms-playwright-go"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        logger.log("Iniciando escaneamento de caches do Playwright", level: .info)
        progress?("Scanning Playwright caches...")
        
        for path in playwrightPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    totalSize += size
                    let name = (path as NSString).lastPathComponent
                    items.append("\(name): \(fileHelper.formatBytes(size))")
                    logger.log("Encontrado: \(name) - \(fileHelper.formatBytes(size))", level: .debug)
                }
            }
        }
        
        logger.log("Escaneamento Playwright concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        
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
        
        logger.log("Iniciando limpeza de caches do Playwright", level: .info)
        
        for path in playwrightPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                do {
                    try fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                    logger.log("Removido: \(path) (\(fileHelper.formatBytes(size)))", level: .debug)
                } catch {
                    errors.append("Falha ao limpar: \(path)")
                    logger.log("Falha ao remover: \(expandedPath)", level: .error)
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        logger.log("Limpeza Playwright concluída: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)
        
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
