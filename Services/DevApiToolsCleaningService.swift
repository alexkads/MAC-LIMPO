import Foundation

/// Service to clean API development tools caches
/// Covers Postman, Insomnia, Bruno, Hoppscotch, and similar REST clients
class DevApiToolsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .devApiTools
    
    private let apiTools: [(name: String, paths: [String])] = [
        ("Postman", [
            "~/Library/Application Support/Postman/Partitions",
            "~/Library/Application Support/Postman/logs",
            "~/Library/Application Support/Postman/Code Cache",
            "~/Library/Application Support/Postman/GPUCache",
            "~/Library/Application Support/Postman/DawnCache",
            "~/Library/Caches/com.postmanlabs.mac"
        ]),
        ("Insomnia", [
            "~/Library/Application Support/Insomnia/Cache",
            "~/Library/Application Support/Insomnia/Code Cache",
            "~/Library/Application Support/Insomnia/GPUCache",
            "~/Library/Application Support/Insomnia/Partitions",
            "~/Library/Caches/com.insomnia.app"
        ]),
        ("Bruno", [
            "~/Library/Application Support/Bruno/Cache",
            "~/Library/Application Support/Bruno/Code Cache",
            "~/Library/Application Support/Bruno/GPUCache",
            "~/Library/Caches/com.usebruno.app"
        ]),
        ("Hoppscotch", [
            "~/Library/Application Support/Hoppscotch/Cache",
            "~/Library/Application Support/Hoppscotch/Code Cache",
            "~/Library/Application Support/Hoppscotch/GPUCache"
        ]),
        ("RapidAPI (Paw)", [
            "~/Library/Caches/com.luckymarmot.Paw",
            "~/Library/Caches/com.paw.Paw"
        ])
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        logger.log("Iniciando escaneamento de ferramentas de API", level: .info)
        
        for (name, paths) in apiTools {
            progress?("Scanning \(name)...")
            var toolSize: Int64 = 0
            
            for path in paths {
                let expandedPath = fileHelper.expandPath(path)
                if fileHelper.fileExists(atPath: expandedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                    toolSize += size
                }
            }
            
            if toolSize > 0 {
                totalSize += toolSize
                items.append("\(name): \(fileHelper.formatBytes(toolSize))")
                logger.log("\(name) cache: \(fileHelper.formatBytes(toolSize))", level: .debug)
            }
        }
        
        logger.log("Escaneamento de API tools concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        
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
        
        logger.log("Iniciando limpeza de ferramentas de API", level: .info)
        
        for (name, paths) in apiTools {
            for path in paths {
                let expandedPath = fileHelper.expandPath(path)
                if fileHelper.fileExists(atPath: expandedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                    
                    // For Partitions folder (Electron cache), clean contents instead of folder
                    let folderName = (expandedPath as NSString).lastPathComponent
                    if folderName == "Partitions" || folderName == "logs" {
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
                        logger.log("Limpo \(name) \(folderName): \(fileHelper.formatBytes(size))", level: .debug)
                    } else {
                        do {
                            try fileHelper.removeItem(atPath: expandedPath)
                            bytesRemoved += size
                            filesRemoved += 1
                            logger.log("Removido \(name) cache (\(folderName)): \(fileHelper.formatBytes(size))", level: .debug)
                        } catch {
                            errors.append("Falha ao limpar \(name): \(error.localizedDescription)")
                            logger.log("Falha ao remover \(name): \(error.localizedDescription)", level: .error)
                        }
                    }
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        logger.log("Limpeza de API tools concluída: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)
        
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
