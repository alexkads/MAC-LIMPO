import Foundation

class TempFilesCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .tempFiles
    
    private let tempPaths = [
        "/tmp",
        "~/Library/Caches/com.apple.bird",  // iCloud
        "~/Library/Caches/CloudKit",
        "~/Library/Caches/com.apple.Safari/Webpage Previews"
    ]
    
    // NÃO limpar estes diretórios (críticos para o sistema)
    private let excludedPaths = [
        "com.apple.dock",
        "com.apple.finder",
        "com.apple.Safari",  // Exceto o subdiretório específico acima
        "com.apple.loginwindow",
        "com.apple.bird",  // Exceto o específico acima
        "com.apple.Music",
        "com.apple.Photos"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        Logger.shared.scan(category: "TempFiles", message: "Starting scan")
        
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for path in tempPaths {
            let expandedPath = fileHelper.expandPath(path)
            
            Logger.shared.debug("Scanning path: \(expandedPath)")
            
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    totalSize += size
                    let pathName = (path as NSString).lastPathComponent
                    let formatted = fileHelper.formatBytes(size)
                    items.append("\(pathName): \(formatted)")
                    Logger.shared.debug("Found: \(pathName) - \(formatted)")
                }
            } else {
                Logger.shared.debug("Path does not exist: \(expandedPath)")
            }
        }
        
        // Adiciona /tmp separadamente
        let tmpPath = "/tmp"
        if fileHelper.fileExists(atPath: tmpPath) {
            let size = fileHelper.sizeOfDirectory(atPath: tmpPath)
            if size > 0 {
                totalSize += size
                items.append("tmp: \(fileHelper.formatBytes(size))")
            }
        }
        
        Logger.shared.scan(category: "TempFiles", message: "Scan complete: \(fileHelper.formatBytes(totalSize)) in \(items.count) locations")
        
        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: items.count,
            items: items
        )
    }
    
    func clean() async -> CleaningResult {
        Logger.shared.clean(category: "TempFiles", message: "Starting cleanup")
        
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []
        
        // Limpa /tmp com cuidado
        Logger.shared.debug("Cleaning /tmp directory")
        await cleanTmpDirectory(bytesRemoved: &bytesRemoved, filesRemoved: &filesRemoved, errors: &errors)
        
        // Limpa outros caches seguros
        for path in tempPaths {
            let expandedPath = fileHelper.expandPath(path)
            
            Logger.shared.debug("Cleaning: \(expandedPath)")
            
            if fileHelper.fileExists(atPath: expandedPath) {
                await cleanDirectory(
                    atPath: expandedPath,
                    bytesRemoved: &bytesRemoved,
                    filesRemoved: &filesRemoved,
                    errors: &errors
                )
            } else {
                Logger.shared.debug("Path does not exist, skipping: \(expandedPath)")
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        
        // Considera sucesso se conseguiu limpar algo OU se não havia nada para limpar
        let success = filesRemoved > 0 || (errors.isEmpty && filesRemoved == 0)
        
        if success {
            Logger.shared.success("TempFiles cleanup complete: \(fileHelper.formatBytes(bytesRemoved)), \(filesRemoved) files, \(errors.count) errors")
        } else {
            Logger.shared.error("TempFiles cleanup failed with \(errors.count) errors")
            for error in errors {
                Logger.shared.error("  - \(error)")
            }
        }
        
        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: executionTime,
            success: success
        )
    }
    
    private func cleanTmpDirectory(bytesRemoved: inout Int64, filesRemoved: inout Int, errors: inout [String]) async {
        let tmpPath = "/tmp"
        let contents = fileHelper.contentsOfDirectory(atPath: tmpPath)
        
        Logger.shared.debug("Found \(contents.count) items in /tmp")
        
        // Limpa apenas arquivos/pastas antigas em /tmp (mais de 7 dias)
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        var skipped = 0
        var removed = 0
        
        for item in contents {
            // Pula itens do sistema
            if item.hasPrefix(".") || item.hasPrefix("com.apple.") {
                skipped += 1
                continue
            }
            
            let itemPath = (tmpPath as NSString).appendingPathComponent(item)
            
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: itemPath)
                
                // Verifica data de modificação
                if let modificationDate = attributes[.modificationDate] as? Date {
                    if modificationDate < cutoffDate {
                        let size = fileHelper.sizeOfDirectory(atPath: itemPath)
                        
                        try fileHelper.removeItem(atPath: itemPath)
                        bytesRemoved += size
                        filesRemoved += 1
                        removed += 1
                        
                        Logger.shared.debug("Removed from /tmp: \(item) (\(fileHelper.formatBytes(size)))")
                    } else {
                        skipped += 1
                    }
                }
            } catch let error as NSError {
                // Para /tmp, ignora TODOS os erros de permissão silenciosamente
                // pois é esperado ter arquivos protegidos aqui
                if (error.domain == NSCocoaErrorDomain && (error.code == 513 || error.code == 257)) ||
                   (error.domain == NSPOSIXErrorDomain && (error.code == 1 || error.code == 13)) {
                    Logger.shared.debug("Permission denied (expected) in /tmp: \(item)")
                } else {
                    Logger.shared.debug("Could not process /tmp item: \(item) - \(error.localizedDescription)")
                }
                skipped += 1
                continue
            }
        }
        
        Logger.shared.info("/tmp cleanup: removed \(removed), skipped \(skipped)")
    }
    
    private func cleanDirectory(atPath path: String, bytesRemoved: inout Int64, filesRemoved: inout Int, errors: inout [String]) async {
        let contents = fileHelper.contentsOfDirectory(atPath: path)
        
        Logger.shared.debug("Cleaning directory: \(path) (\(contents.count) items)")
        
        var removed = 0
        var skipped = 0
        
        for item in contents {
            // Pula arquivos ocultos e do sistema
            if item.hasPrefix(".") {
                skipped += 1
                continue
            }
            
            let itemPath = (path as NSString).appendingPathComponent(item)
            
            // Verifica se está na lista de exclusão
            var shouldSkip = false
            for excluded in excludedPaths {
                if itemPath.contains(excluded) {
                    shouldSkip = true
                    Logger.shared.debug("Skipping excluded path: \(itemPath)")
                    break
                }
            }
            
            if shouldSkip {
                skipped += 1
                continue
            }
            
            do {
                // Calcula tamanho ANTES de remover
                let size = fileHelper.sizeOfDirectory(atPath: itemPath)
                
                // Remove o item
                try fileHelper.removeItem(atPath: itemPath)
                
                // Só conta se conseguiu remover
                bytesRemoved += size
                filesRemoved += 1
                removed += 1
                
                Logger.shared.debug("Removed: \(item) (\(fileHelper.formatBytes(size)))")
            } catch let error as NSError {
                let itemName = (itemPath as NSString).lastPathComponent
                
                // Diferencia entre erros de permissão (esperados) e erros reais
                if error.domain == NSCocoaErrorDomain && (error.code == 513 || error.code == 257) {
                    // 513 = NSFileWriteNoPermissionError
                    // 257 = NSFileReadNoPermissionError
                    Logger.shared.debug("Permission denied (expected): \(itemName)")
                    skipped += 1
                } else if error.domain == NSPOSIXErrorDomain && (error.code == 1 || error.code == 13) {
                    // 1 = EPERM (Operation not permitted)
                    // 13 = EACCES (Permission denied)
                    Logger.shared.debug("Permission denied (expected): \(itemName)")
                    skipped += 1
                } else {
                    // Erro real - reporta ao usuário
                    let errorMsg = "Failed to remove \(itemName): \(error.localizedDescription)"
                    errors.append(errorMsg)
                    Logger.shared.warning(errorMsg)
                    skipped += 1
                }
            }
        }
        
        Logger.shared.info("Directory \(path): removed \(removed), skipped \(skipped)")
    }
}
