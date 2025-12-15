import Foundation

class LogsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .logs
    
    private let logPaths = [
        "~/Library/Logs",
        "~/Library/Application Support/CrashReporter",
        "~/Library/Logs/Adobe",
        "~/Library/Logs/DiagnosticReports",
        "/Library/Logs/DiagnosticReports",
        "~/Library/Containers/*/Data/Library/Logs",
        "/var/log/system.log",
        "/var/log/install.log"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for path in logPaths {
            // Resolve wildcards
            let paths = resolvePaths(path)
            
            for expandedPath in paths {
                if fileHelper.fileExists(atPath: expandedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                    if size > 0 {
                        totalSize += size
                        let pathName = (expandedPath as NSString).lastPathComponent
                        items.append("\(pathName): \(fileHelper.formatBytes(size))")
                    }
                }
            }
        }
        
        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: items.count,
            items: items
        )
    }
    
    private func resolvePaths(_ path: String) -> [String] {
        let expanded = fileHelper.expandPath(path)
        
        if path.contains("*") {
            let components = expanded.components(separatedBy: "/*")
            if components.count >= 2 {
                let baseFolder = components[0]
                let remainingPath = components.dropFirst().joined(separator: "/")
                
                let contents = fileHelper.contentsOfDirectory(atPath: baseFolder)
                var results: [String] = []
                
                for item in contents {
                    let itemPath = (baseFolder as NSString).appendingPathComponent(item)
                    let finalPath = (itemPath as NSString).appendingPathComponent(remainingPath)
                    if fileHelper.fileExists(atPath: finalPath) {
                        results.append(finalPath)
                    }
                }
                return results
            }
        }
        
        return [expanded]
    }
    
    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []
        
        // Limpa logs com mais de 30 dias
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        for path in logPaths {
            let paths = resolvePaths(path)
            
            for expandedPath in paths {
                // Pula caminhos do sistema que requerem sudo
                if expandedPath.hasPrefix("/var/log") || expandedPath.hasPrefix("/Library/Logs") {
                    continue
                }
                
                let contents = fileHelper.contentsOfDirectory(atPath: expandedPath)
                
                for item in contents {
                    let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                    
                    // Verifica data de modificação
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
                        errors.append("Failed to clean log \(item): \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Nota: Limpeza de logs do sistema requer permissões especiais
        // e não pode ser feita sem intervenção do usuário via sudo
        // Por isso, essa funcionalidade foi desabilitada
        
        // Se você quiser adicionar suporte, precisará:
        // 1. Criar um helper tool com privilégios elevados
        // 2. Usar SMJobBless para instalá-lo
        // 3. Comunicar via XPC com o helper
        
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
