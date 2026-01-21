import Foundation

/// Service to clean AI and LLM tools caches
/// Covers Claude, Antigravity (Gemini), Trae, Cursor AI, and similar tools
class AIToolsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .aiTools
    
    // AI tools and their cache locations
    private let aiToolsCaches: [(name: String, paths: [String])] = [
        ("Claude", [
            "~/Library/Application Support/Claude/Cache",
            "~/Library/Application Support/Claude/Code Cache",
            "~/Library/Application Support/Claude/GPUCache",
            "~/Library/Caches/com.anthropic.claudefordesktop",
        ]),
        ("Antigravity (Gemini)", [
            "~/Library/Application Support/Antigravity/Cache",
            "~/Library/Application Support/Antigravity/CachedData",
            "~/Library/Application Support/Antigravity/Code Cache",
            "~/Library/Application Support/Antigravity/GPUCache",
            "~/Library/Caches/com.google.antigravity",
        ]),
        ("Trae", [
            "~/Library/Application Support/Trae/Cache",
            "~/Library/Application Support/Trae/CachedData",
            "~/Library/Application Support/Trae/CachedExtensionVSIXs",
            "~/Library/Application Support/Trae/Code Cache",
            "~/Library/Application Support/Trae/GPUCache",
            "~/Library/Application Support/Trae/logs",
        ]),
        ("Cursor AI", [
            "~/Library/Application Support/Cursor/CachedData",
            "~/Library/Application Support/Cursor/Cache",
            "~/Library/Application Support/Cursor/Code Cache",
            "~/Library/Application Support/Cursor/GPUCache",
            "~/Library/Application Support/Cursor/logs",
        ]),
        ("GitHub Copilot", [
            "~/Library/Caches/com.github.Copilot",
            "~/Library/Application Support/github-copilot",
        ]),
        ("Codeium", [
            "~/Library/Caches/codeium",
            "~/Library/Application Support/Codeium",
        ]),
        ("Tabnine", [
            "~/.tabnine",
            "~/Library/Caches/com.tabnine.TabNine",
        ]),
        ("Amazon Q", [
            "~/Library/Application Support/Amazon Q",
            "~/Library/Caches/com.amazon.codewhisperer",
        ]),
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        Logger.shared.scan(category: "AITools", message: "Starting scan")
        
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for (name, paths) in aiToolsCaches {
            var toolSize: Int64 = 0
            var found = false
            
            for path in paths {
                let expandedPath = fileHelper.expandPath(path)
                
                if fileHelper.fileExists(atPath: expandedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                    if size > 0 {
                        toolSize += size
                        found = true
                    }
                }
            }
            
            if found && toolSize > 0 {
                totalSize += toolSize
                items.append("\(name): \(fileHelper.formatBytes(toolSize))")
                Logger.shared.debug("Found \(name): \(fileHelper.formatBytes(toolSize))")
            }
            
            progress?("Scanning \(name)...")
        }
        
        Logger.shared.scan(category: "AITools", message: "Scan complete: \(fileHelper.formatBytes(totalSize))")
        
        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: items.count,
            items: items
        )
    }
    
    func clean() async -> CleaningResult {
        Logger.shared.clean(category: "AITools", message: "Starting cleanup")
        
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        let errors: [String] = []
        
        for (name, paths) in aiToolsCaches {
            for path in paths {
                let expandedPath = fileHelper.expandPath(path)
                
                if fileHelper.fileExists(atPath: expandedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                    
                    // Clean contents, not the folder itself
                    let contents = fileHelper.contentsOfDirectory(atPath: expandedPath)
                    
                    for item in contents {
                        let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                        
                        do {
                            try fileHelper.removeItem(atPath: itemPath)
                            filesRemoved += 1
                        } catch {
                            // Ignore permission errors silently
                            Logger.shared.debug("Could not remove \(item): \(error.localizedDescription)")
                        }
                    }
                    
                    bytesRemoved += size
                    Logger.shared.debug("Cleaned \(name): \(fileHelper.formatBytes(size))")
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        
        Logger.shared.success("AITools cleanup complete: \(fileHelper.formatBytes(bytesRemoved))")
        
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
