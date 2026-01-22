import Foundation

/// Service to clean leftovers from uninstalled applications
class AppLeftoversCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .appLeftovers
    
    // Known apps to check for leftovers
    // (AppName, Application Support Path, Mac App Path)
    // Note: JetBrains is handled efficiently via special logic, but kept here for structure
    private let knownApps = [
        ("Cursor", "~/Library/Application Support/Cursor", "/Applications/Cursor.app"),
        ("Trae", "~/Library/Application Support/Trae", "/Applications/Trae.app"),
        ("VS Code", "~/Library/Application Support/Code", "/Applications/Visual Studio Code.app"),
        ("Android Studio", "~/Library/Application Support/Google/AndroidStudio*", "/Applications/Android Studio.app"),
        ("Zoom", "~/Library/Application Support/zoom.us", "/Applications/zoom.us.app"),
        ("Discord", "~/Library/Application Support/discord", "/Applications/Discord.app"),
        ("Slack", "~/Library/Application Support/Slack", "/Applications/Slack.app"),
        ("Postman", "~/Library/Application Support/Postman", "/Applications/Postman.app"),
        ("Docker", "~/Library/Application Support/Docker Desktop", "/Applications/Docker.app"),
        // Added Android SDK Root (big 16GB leftover)
        ("Android SDK", "~/Library/Android", "/Applications/Android Studio.app"),
        // Additional Leftovers found
        ("Visual Studio", "~/Library/Application Support/VisualStudio", "/Applications/Visual Studio.app"),
        ("Zed", "~/Library/Application Support/Zed", "/Applications/Zed.app")
    ]
    
    // Map of JetBrains folder prefixes to their Application names
    private let jetBrainsAppMap: [String: String] = [
        "IntelliJ": "IntelliJ IDEA.app",
        "IdeaIC": "IntelliJ IDEA CE.app",
        "PyCharm": "PyCharm.app",
        "PyCharmCE": "PyCharm CE.app",
        "WebStorm": "WebStorm.app",
        "Rider": "Rider.app",
        "GoLand": "GoLand.app",
        "DataGrip": "DataGrip.app",
        "RubyMine": "RubyMine.app",
        "RustRover": "RustRover.app",
        "CLion": "CLion.app",
        "PhpStorm": "PhpStorm.app",
        "Aqua": "Aqua.app"
    ]
    
    private func isAppInstalled(path: String) -> Bool {
        return fileHelper.fileExists(atPath: path)
    }
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        Logger.shared.log("Scanning for app leftovers...", level: .info)
        
        // 1. Scan Standard Apps
        for (name, appSupportPath, appPath) in knownApps {
            progress?("Checking \(name)...")
            
            // Handle wildcard paths (e.g. AndroidStudio*)
            let expandedPath = fileHelper.expandPath(appSupportPath)
            var pathsToCheck: [String] = []
            
            if appSupportPath.contains("*") {
                let parent = (expandedPath as NSString).deletingLastPathComponent
                let pattern = (expandedPath as NSString).lastPathComponent.replacingOccurrences(of: "*", with: "")
                
                if fileHelper.fileExists(atPath: parent) {
                    let contents = fileHelper.contentsOfDirectory(atPath: parent)
                    for item in contents {
                        if item.contains(pattern) {
                            pathsToCheck.append((parent as NSString).appendingPathComponent(item))
                        }
                    }
                }
            } else {
                pathsToCheck = [expandedPath]
            }
            
            for path in pathsToCheck {
                if fileHelper.fileExists(atPath: path) {
                    // Check if app installed
                    if !isAppInstalled(path: appPath) {
                        let size = fileHelper.sizeOfDirectory(atPath: path)
                        if size > 0 {
                            totalSize += size
                            items.append("\(name) (Leftover): \(fileHelper.formatBytes(size))")
                            Logger.shared.log("Found leftover: \(name) at \(path)", level: .debug)
                        }
                    }
                }
            }
        }
        
        // 2. Scan JetBrains Granularly
        progress?("Checking JetBrains Products...")
        let jetBrainsRoot = fileHelper.expandPath("~/Library/Application Support/JetBrains")
        if fileHelper.fileExists(atPath: jetBrainsRoot) {
            let contents = fileHelper.contentsOfDirectory(atPath: jetBrainsRoot)
            
            for item in contents {
                // item is e.g. "Rider2024.1", "WebStorm2023.2", "PartPending"
                let itemPath = (jetBrainsRoot as NSString).appendingPathComponent(item)
                
                // Skip non-directories if any
                // Map item name to app
                var matchedApp: String? = nil
                
                for (prefix, appName) in jetBrainsAppMap {
                    if item.starts(with: prefix) {
                        matchedApp = "/Applications/\(appName)"
                        break
                    }
                }
                
                // Also check Toolbox
                if item == "Toolbox" {
                    matchedApp = "/Applications/JetBrains Toolbox.app"
                }
                
                if let appPath = matchedApp {
                    if !isAppInstalled(path: appPath) {
                        // LEFTOVER!
                        let size = fileHelper.sizeOfDirectory(atPath: itemPath)
                        if size > 0 {
                            totalSize += size
                            items.append("JetBrains \(item) (Leftover): \(fileHelper.formatBytes(size))")
                             Logger.shared.log("Found JetBrains leftover: \(item) at \(itemPath)", level: .debug)
                        }
                    }
                } else {
                    // Unknown folder in JetBrains? Ideally we leave it or check if it's safe.
                    // For now, only delete what we KNOW matches a missing app.
                    // "ConsentOptions", "bl", "crl" are meta folders, safer to keep if unsure, 
                    // OR if ALL IDEs are gone, maybe delete root? 
                    // Taking safe approach: Only delete recognized product folders whose app is missing.
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
        
        // 1. Clean Standard Apps
        for (name, appSupportPath, appPath) in knownApps {
             let expandedPath = fileHelper.expandPath(appSupportPath)
             var pathsToCheck: [String] = []
             
             if appSupportPath.contains("*") {
                 let parent = (expandedPath as NSString).deletingLastPathComponent
                 let pattern = (expandedPath as NSString).lastPathComponent.replacingOccurrences(of: "*", with: "")
                 if fileHelper.fileExists(atPath: parent) {
                     let contents = fileHelper.contentsOfDirectory(atPath: parent)
                     for item in contents {
                         if item.contains(pattern) {
                             pathsToCheck.append((parent as NSString).appendingPathComponent(item))
                         }
                     }
                 }
             } else {
                 pathsToCheck = [expandedPath]
             }
            
            for path in pathsToCheck {
               if fileHelper.fileExists(atPath: path) {
                   if !isAppInstalled(path: appPath) {
                       let size = fileHelper.sizeOfDirectory(atPath: path)
                       do {
                           try fileHelper.removeItem(atPath: path)
                           bytesRemoved += size
                           filesRemoved += 1
                           Logger.shared.log("Deleted leftover: \(path)", level: .info)
                       } catch {
                           Logger.shared.log("Failed to delete leftover \(path): \(error)", level: .error)
                           errors.append("Failed to delete \(name): \(error.localizedDescription)")
                       }
                   }
               }
            }
        }
        
        // 2. Clean JetBrains Granularly
        let jetBrainsRoot = fileHelper.expandPath("~/Library/Application Support/JetBrains")
        if fileHelper.fileExists(atPath: jetBrainsRoot) {
            let contents = fileHelper.contentsOfDirectory(atPath: jetBrainsRoot)
            
            for item in contents {
                let itemPath = (jetBrainsRoot as NSString).appendingPathComponent(item)
                var matchedApp: String? = nil
                
                for (prefix, appName) in jetBrainsAppMap {
                    if item.starts(with: prefix) {
                        matchedApp = "/Applications/\(appName)"
                        break
                    }
                }
                
                if item == "Toolbox" { matchedApp = "/Applications/JetBrains Toolbox.app" }
                
                if let appPath = matchedApp {
                    if !isAppInstalled(path: appPath) {
                        let size = fileHelper.sizeOfDirectory(atPath: itemPath)
                        do {
                            try fileHelper.removeItem(atPath: itemPath)
                            bytesRemoved += size
                            filesRemoved += 1
                            Logger.shared.log("Deleted JetBrains leftover: \(item)", level: .info)
                        } catch {
                            Logger.shared.log("Failed to delete JB leftover \(item): \(error)", level: .error)
                             errors.append("Failed to delete JB \(item): \(error.localizedDescription)")
                        }
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
            success: true
        )
    }
}
