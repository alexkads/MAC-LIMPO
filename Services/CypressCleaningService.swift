import Foundation

/// Service to clean Cypress end-to-end testing framework caches
/// Covers test results cache, Electron cache, and browser download cache
class CypressCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .cypress
    
    // Cypress test data and cache (safe to clean - recreated on next test run)
    private let cypressTestDataPaths = [
        "~/Library/Application Support/Cypress/cy",
        "~/Library/Application Support/Cypress/Partitions",
        "~/Library/Application Support/Cypress/DawnCache",
        "~/Library/Application Support/Cypress/GPUCache",
        "~/Library/Application Support/Cypress/Code Cache"
    ]
    
    // Cypress binary cache (~/.cache/Cypress)
    private let cypressBinaryPaths = [
        "~/.cache/Cypress"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        logger.log("Iniciando escaneamento do Cypress", level: .info)
        
        // Scan test data cache
        progress?("Scanning Cypress test data...")
        var testDataSize: Int64 = 0
        for path in cypressTestDataPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                testDataSize += size
            }
        }
        if testDataSize > 0 {
            totalSize += testDataSize
            items.append("Cypress test data & Electron cache: \(fileHelper.formatBytes(testDataSize))")
            logger.log("Cypress test data: \(fileHelper.formatBytes(testDataSize))", level: .debug)
        }
        
        // Scan binary cache
        progress?("Scanning Cypress binary cache...")
        var binarySize: Int64 = 0
        for path in cypressBinaryPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                binarySize += size
            }
        }
        if binarySize > 0 {
            totalSize += binarySize
            items.append("Cypress browser binaries (~/.cache): \(fileHelper.formatBytes(binarySize))")
            logger.log("Cypress binaries: \(fileHelper.formatBytes(binarySize))", level: .debug)
        }
        
        logger.log("Escaneamento Cypress concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        
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
        
        logger.log("Iniciando limpeza do Cypress", level: .info)
        
        // Clean test data (contents only to preserve folder structure)
        for path in cypressTestDataPaths {
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
                let folderName = (expandedPath as NSString).lastPathComponent
                logger.log("Limpo Cypress \(folderName): \(fileHelper.formatBytes(size))", level: .debug)
            }
        }
        
        // Clean binary cache folder
        for path in cypressBinaryPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                do {
                    try fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                    logger.log("Removido Cypress binary cache: \(fileHelper.formatBytes(size))", level: .debug)
                } catch {
                    errors.append("Falha ao limpar Cypress binaries: \(error.localizedDescription)")
                    logger.log("Falha ao remover Cypress binaries: \(error.localizedDescription)", level: .error)
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        logger.log("Limpeza Cypress concluída: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)
        
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
