import Foundation

class TerminalLogsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .terminalLogs
    
    private let terminalLogPaths = [
        "~/Library/Logs/warp.log",
        "~/Library/Logs/warp.log.old.0",
        "~/Library/Logs/warp.log.old.1",
        "~/Library/Logs/warp.log.old.2",
        "~/Library/Logs/warp.log.old.3",
        "~/Library/Logs/warp.log.old.4"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        logger.log("Iniciando escaneamento de logs de terminal", level: .info)
        progress?("Scanning terminal logs...")
        
        for path in terminalLogPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: expandedPath)
                    if let size = attrs[.size] as? Int64, size > 0 {
                        totalSize += size
                    }
                } catch {
                    continue
                }
            }
        }
        
        if totalSize > 0 {
            items.append("Warp terminal logs: \(fileHelper.formatBytes(totalSize))")
        }
        
        logger.log("Escaneamento terminal logs concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        
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
        
        logger.log("Iniciando limpeza de logs de terminal", level: .info)
        
        for path in terminalLogPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: expandedPath)
                    let size = attrs[.size] as? Int64 ?? 0
                    try fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                    logger.log("Removido: \(path) (\(fileHelper.formatBytes(size)))", level: .debug)
                } catch {
                    logger.log("Não foi possível remover: \(path)", level: .debug)
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        logger.log("Limpeza terminal logs concluída: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)
        
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
