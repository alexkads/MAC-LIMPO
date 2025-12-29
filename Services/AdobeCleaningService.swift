import Foundation

class AdobeCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .adobeCache
    let logger = Logger.shared
    
    private let adobePaths = [
        "~/Library/Caches/Adobe",
        "~/Library/Caches/com.adobe.*",
        "~/Library/Application Support/Adobe/Common/Media Cache Files",
        "~/Library/Application Support/Adobe/Common/Media Cache",
        "~/Library/Application Support/Adobe/Common/Peak Files",
        "~/Library/Logs/Adobe"
    ]
    
    private func resolvePaths(_ path: String) -> [String] {
        let expanded = fileHelper.expandPath(path)
        
        // Handle wildcard patterns
        if path.contains("*") {
            let parentDir = (expanded as NSString).deletingLastPathComponent
            let pattern = (expanded as NSString).lastPathComponent
            
            guard fileHelper.fileExists(atPath: parentDir) else { return [] }
            
            let contents = fileHelper.contentsOfDirectory(atPath: parentDir)
            var results: [String] = []
            
            for item in contents {
                if item.range(of: pattern.replacingOccurrences(of: "*", with: ".*"), options: .regularExpression) != nil {
                    let fullPath = (parentDir as NSString).appendingPathComponent(item)
                    if fileHelper.fileExists(atPath: fullPath) {
                        results.append(fullPath)
                    }
                }
            }
            return results
        }
        
        return [expanded]
    }
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        logger.log("Iniciando scan de caches da Adobe", level: .info)
        
        for path in adobePaths {
            progress?("Scanning Adobe: \(path)")
            
            for resolvedPath in resolvePaths(path) {
                if fileHelper.fileExists(atPath: resolvedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: resolvedPath)
                    if size > 0 {
                        totalSize += size
                        let displayName = (resolvedPath as NSString).lastPathComponent
                        items.append("\(displayName): \(fileHelper.formatBytes(size))")
                        logger.log("Encontrado: \(displayName) - \(fileHelper.formatBytes(size))", level: .debug)
                    }
                }
            }
        }
        
        if items.isEmpty {
            items.append("No Adobe cache found")
            logger.log("Nenhum cache da Adobe encontrado", level: .info)
        } else {
            logger.log("Scan concluído: \(fileHelper.formatBytes(totalSize)) em \(items.count) itens", level: .info)
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
        
        logger.log("Iniciando limpeza de caches da Adobe", level: .info)
        
        for path in adobePaths {
            for resolvedPath in resolvePaths(path) {
                if fileHelper.fileExists(atPath: resolvedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: resolvedPath)
                    
                    do {
                        var isDirectory: ObjCBool = false
                        FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory)
                        
                        if isDirectory.boolValue {
                            // Para diretórios de cache, remover conteúdo mas manter a estrutura
                            let contents = try FileManager.default.contentsOfDirectory(atPath: resolvedPath)
                            for item in contents {
                                let itemPath = (resolvedPath as NSString).appendingPathComponent(item)
                                try fileHelper.removeItem(atPath: itemPath)
                                filesRemoved += 1
                            }
                        } else {
                            // Para arquivos, remover diretamente
                            try fileHelper.removeItem(atPath: resolvedPath)
                            filesRemoved += 1
                        }
                        
                        bytesRemoved += size
                        logger.log("Removido: \(resolvedPath) - \(fileHelper.formatBytes(size))", level: .debug)
                    } catch {
                        let errorMsg = "Failed to clean \(resolvedPath): \(error.localizedDescription)"
                        errors.append(errorMsg)
                        logger.log(errorMsg, level: .error)
                    }
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        
        logger.log("Limpeza concluída: \(fileHelper.formatBytes(bytesRemoved)) removidos em \(String(format: "%.2f", executionTime))s", level: .info)
        
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
