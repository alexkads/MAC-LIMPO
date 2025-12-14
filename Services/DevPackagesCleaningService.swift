import Foundation

class DevPackagesCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .devPackages
    
    private let cachePaths = [
        ("npm", "~/.npm"),
        ("pip", "~/Library/Caches/pip"),
        ("Homebrew", "~/Library/Caches/Homebrew"),
        ("Cargo", "~/.cargo/registry/cache"),
        ("CocoaPods", "~/Library/Caches/CocoaPods")
    ]
    
    func scan() async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for (name, path) in cachePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    totalSize += size
                    items.append("\(name): \(fileHelper.formatBytes(size))")
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
    
    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []
        
        for (name, path) in cachePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let sizeBeforeRemoval = fileHelper.sizeOfDirectory(atPath: expandedPath)
                let fileCount = fileHelper.countFiles(inDirectory: expandedPath)
                
                do {
                    try fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += sizeBeforeRemoval
                    filesRemoved += fileCount
                } catch {
                    errors.append("Failed to clean \(name): \(error.localizedDescription)")
                }
            }
        }
        
        // Limpa npm cache via comando
        if shell.checkCommandExists("npm") {
            let npmResult = shell.execute("npm cache clean --force")
            if npmResult.exitCode != 0 {
                errors.append("npm cache clean failed: \(npmResult.error)")
            }
        }
        
        // Limpa Homebrew
        if shell.checkCommandExists("brew") {
            let brewResult = shell.execute("brew cleanup -s")
            if brewResult.exitCode == 0 {
                // Tenta extrair bytes removidos do output
                let lines = brewResult.output.components(separatedBy: "\n")
                for line in lines {
                    if line.contains("freed") || line.contains("removed") {
                        // Adiciona aos removidos
                        filesRemoved += 1
                    }
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        
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
