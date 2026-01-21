import Foundation

/// Service to clean /private/var/folders caches
/// This directory contains per-process temporary caches that can grow very large
class VarFoldersCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .varFolders
    
    // Safe caches to clean in /private/var/folders
    private let safeToCleanPatterns = [
        "com.google.Chrome.code_sign_clone",
        "com.google.Chrome.helper",
        "org.chromium.Chromium.helper",
        "SpeechModelCache",
        "clang",
        "com.apple.metal",
        "com.apple.wallpaper.caches",
        "com.microsoft.teams2",
        "desktop.WhatsApp",
        "net.whatsapp.WhatsApp",
        "com.apple.Safari.SafeBrowsing",
        "com.apple.dock.iconcache",
        "com.github.Electron.helper",
        "com.canva.affinity",
        "com.apple.GenerativePlaygroundApp",
        "com.jetbrains",
        "com.spotify",
        "com.discord",
    ]
    
    // Never clean these (critical for system)
    private let neverClean = [
        "com.apple.launchd",
        "com.apple.Finder",
        "com.apple.loginwindow",
        "com.apple.WindowServer",
        "com.apple.kernel",
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        Logger.shared.scan(category: "VarFolders", message: "Starting scan of /private/var/folders")
        
        var totalSize: Int64 = 0
        var items: [String] = []
        
        // Find the user's folder in /private/var/folders
        let varFoldersPath = "/private/var/folders"
        
        guard fileHelper.fileExists(atPath: varFoldersPath) else {
            return ScanResult(category: category, estimatedSize: 0, itemCount: 0, items: [])
        }
        
        // Scan C (Caches), T (Temporary), X (other) subdirectories
        let subDirs = ["C", "T", "X"]
        
        for folder in fileHelper.contentsOfDirectory(atPath: varFoldersPath) {
            let level1Path = (varFoldersPath as NSString).appendingPathComponent(folder)
            
            for subFolder in fileHelper.contentsOfDirectory(atPath: level1Path) {
                let level2Path = (level1Path as NSString).appendingPathComponent(subFolder)
                
                for subDir in subDirs {
                    let targetPath = (level2Path as NSString).appendingPathComponent(subDir)
                    
                    if fileHelper.fileExists(atPath: targetPath) {
                        for item in fileHelper.contentsOfDirectory(atPath: targetPath) {
                            let itemPath = (targetPath as NSString).appendingPathComponent(item)
                            
                            // Check if it matches safe patterns
                            let isSafe = safeToCleanPatterns.contains { pattern in
                                item.contains(pattern)
                            }
                            
                            // Skip if in never clean list
                            let isProtected = neverClean.contains { pattern in
                                item.contains(pattern)
                            }
                            
                            if isSafe && !isProtected {
                                let size = fileHelper.sizeOfDirectory(atPath: itemPath)
                                if size > 1_000_000 { // Only count if > 1MB
                                    totalSize += size
                                    items.append("\(item): \(fileHelper.formatBytes(size))")
                                    Logger.shared.debug("Found: \(item) - \(fileHelper.formatBytes(size))")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        Logger.shared.scan(category: "VarFolders", message: "Scan complete: \(fileHelper.formatBytes(totalSize))")
        
        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: items.count,
            items: items
        )
    }
    
    func clean() async -> CleaningResult {
        Logger.shared.clean(category: "VarFolders", message: "Starting cleanup")
        
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        let errors: [String] = []
        
        let varFoldersPath = "/private/var/folders"
        let subDirs = ["C", "T", "X"]
        
        for folder in fileHelper.contentsOfDirectory(atPath: varFoldersPath) {
            let level1Path = (varFoldersPath as NSString).appendingPathComponent(folder)
            
            for subFolder in fileHelper.contentsOfDirectory(atPath: level1Path) {
                let level2Path = (level1Path as NSString).appendingPathComponent(subFolder)
                
                for subDir in subDirs {
                    let targetPath = (level2Path as NSString).appendingPathComponent(subDir)
                    
                    if fileHelper.fileExists(atPath: targetPath) {
                        for item in fileHelper.contentsOfDirectory(atPath: targetPath) {
                            let itemPath = (targetPath as NSString).appendingPathComponent(item)
                            
                            let isSafe = safeToCleanPatterns.contains { pattern in
                                item.contains(pattern)
                            }
                            
                            let isProtected = neverClean.contains { pattern in
                                item.contains(pattern)
                            }
                            
                            if isSafe && !isProtected {
                                let size = fileHelper.sizeOfDirectory(atPath: itemPath)
                                
                                if size > 1_000_000 {
                                    do {
                                        // Clean contents, not the folder itself
                                        for subItem in fileHelper.contentsOfDirectory(atPath: itemPath) {
                                            let subItemPath = (itemPath as NSString).appendingPathComponent(subItem)
                                            try fileHelper.removeItem(atPath: subItemPath)
                                            filesRemoved += 1
                                        }
                                        bytesRemoved += size
                                        Logger.shared.debug("Cleaned: \(item) - \(fileHelper.formatBytes(size))")
                                    } catch {
                                        // Permission errors are expected, ignore silently
                                        Logger.shared.debug("Could not clean \(item): \(error.localizedDescription)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        
        Logger.shared.success("VarFolders cleanup complete: \(fileHelper.formatBytes(bytesRemoved))")
        
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
