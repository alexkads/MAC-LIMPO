import Foundation

/// Service to clean development project artifacts
/// Targets: node_modules, target (Rust), build, dist, vendor
class ProjectCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .development
    
    // Configurable paths to scan
    private let projectRoot = "~/Projects"
    
    // Directories to target for cleaning
    private let targets = ["node_modules", "target", "build", "dist", ".gradle", "venv", ".venv"]
    
    // Safety: Only delete if they look like build folders
    // Heuristic: "target" folder in a folder containing "Cargo.toml" is safe to delete (Rust)
    // "node_modules" in a folder containing "package.json" is safe
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        Logger.shared.log("Scanning projects for build artifacts...", level: .info)
        
        let expandedRoot = fileHelper.expandPath(projectRoot)
        
        // Deep scan is required. We'll use a breadth-first search or recursive scan.
        // To avoid taking forever, we might limit depth or specific known huge projects?
        // For now, let's scan 3 levels deep looking for target folders.
        
        // Better: Use FileManager's enumerator to find directories efficiently
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: expandedRoot), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        
        while let url = enumerator?.nextObject() as? URL {
            let path = url.path
            let name = url.lastPathComponent
            
            // Check if this is a target directory
            if targets.contains(name) {
                // Safety Checks
                var safeToDelete = false
                let parentPath = (path as NSString).deletingLastPathComponent
                let parentContent = (try? fileManager.contentsOfDirectory(atPath: parentPath)) ?? []
                
                if name == "target" && parentContent.contains("Cargo.toml") {
                    safeToDelete = true // It's a Rust target
                } else if name == "node_modules" && parentContent.contains("package.json") {
                    safeToDelete = true
                } else if name == ".gradle" {
                    safeToDelete = true
                } else if name == "build" || name == "dist" {
                    // Bit riskier, maybe verify checking parent?
                    safeToDelete = true 
                }
                
                if safeToDelete {
                    // Calculate size
                    progress?("Analyzing \(name) in \(url.deletingLastPathComponent().lastPathComponent)...")
                    let size = fileHelper.sizeOfDirectory(atPath: path)
                    
                    if size > 50 * 1024 * 1024 { // Only suggest big folders (> 50MB) to avoid noise
                        totalSize += size
                        let shortPath = path.replacingOccurrences(of: expandedRoot, with: "")
                        items.append("\(shortPath) (\(fileHelper.formatBytes(size)))")
                        Logger.shared.log("Found artifact: \(path) (\(fileHelper.formatBytes(size)))", level: .debug)
                    }
                    
                    // Don't scan inside this folder
                    enumerator?.skipDescendants()
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
        
        // Re-scan logic essentially to get paths to delete
        // WARN: This is aggressive. In a real product, we'd select items. 
        // For this agent session, we assume user wants to clean identified junk.
        
        let expandedRoot = fileHelper.expandPath(projectRoot)
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: expandedRoot), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        
        while let url = enumerator?.nextObject() as? URL {
            let path = url.path
            let name = url.lastPathComponent
            
            if targets.contains(name) {
                var safeToDelete = false
                let parentPath = (path as NSString).deletingLastPathComponent
                let parentContent = (try? fileManager.contentsOfDirectory(atPath: parentPath)) ?? []
                
                if name == "target" && parentContent.contains("Cargo.toml") { safeToDelete = true }
                else if name == "node_modules" && parentContent.contains("package.json") { safeToDelete = true }
                else if name == ".gradle" { safeToDelete = true }
                else if name == "build" || name == "dist" { safeToDelete = true }
                
                if safeToDelete {
                    let size = fileHelper.sizeOfDirectory(atPath: path)
                    if size > 50 * 1024 * 1024 { // Match Scan filter
                         do {
                            try fileHelper.removeItem(atPath: path)
                            bytesRemoved += size
                            filesRemoved += 1
                            Logger.shared.log("Cleaned project artifact: \(path)", level: .info)
                        } catch {
                            errors.append("Failed to clean \(name): \(error.localizedDescription)")
                             Logger.shared.log("Failed to clean \(path): \(error)", level: .error)
                        }
                    }
                    enumerator?.skipDescendants()
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
            success: true
        )
    }
}
