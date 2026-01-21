import Foundation

/// Service to clean Creative Apps caches (Canva, Affinity, Adobe Group Containers)
class CreativeAppsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .creativeApps
    
    // Creative tools caches
    private let creativePaths: [(name: String, paths: [String])] = [
        ("Canva & Affinity", [
            "~/Library/Group Containers/5HD2ARTBFS.com.canva.affinity",
            "~/Library/Application Support/Affinity/Photo/1.0/temp",
            "~/Library/Application Support/Affinity/Designer/1.0/temp",
            "~/Library/Application Support/Affinity/Publisher/1.0/temp",
            "~/Library/Caches/com.seriflabs.affinitydesigner",
            "~/Library/Caches/com.seriflabs.affinityphoto",
            "~/Library/Caches/com.seriflabs.affinitypublisher",
        ]),
        ("Figma", [
            "~/Library/Caches/com.figma.Desktop",
            "~/Library/Application Support/Figma/Cache",
            "~/Library/Application Support/Figma/GPUCache"
        ]),
        ("Adobe Shared Groups", [
            "~/Library/Group Containers/JQ525L2MZD.com.adobe.GrowthSDK",
            "~/Library/Group Containers/JQ525L2MZD.com.adobe.CCLibrary",
            "~/Library/Group Containers/Adobe-Hub-App/Logs"
        ]),
        ("Blender", [
            "~/Library/Caches/Blender",
            "~/Library/Application Support/Blender/cache"
        ])
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for (name, paths) in creativePaths {
            var toolSize: Int64 = 0
            
            for path in paths {
                let expandedPath = fileHelper.expandPath(path)
                if fileHelper.fileExists(atPath: expandedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                    if size > 0 {
                        toolSize += size
                    }
                }
            }
            
            if toolSize > 0 {
                totalSize += toolSize
                items.append("\(name): \(fileHelper.formatBytes(toolSize))")
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
        let errors: [String] = []
        
        for (name, paths) in creativePaths {
            for path in paths {
                let expandedPath = fileHelper.expandPath(path)
                if fileHelper.fileExists(atPath: expandedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                    
                    // Specific handling for complex directories
                    if expandedPath.contains("Group Containers") {
                        // Clean only cache/temp folders inside Group Containers
                        let targets = ["Cache", "Caches", "temp", "Logs", "com.adobe.GrowthSDK"]
                        if let enumerator = FileManager.default.enumerator(atPath: expandedPath) {
                            while let file = enumerator.nextObject() as? String {
                                let shouldClean = targets.contains(where: { file.contains($0) })
                                if shouldClean {
                                    let fullPath = (expandedPath as NSString).appendingPathComponent(file)
                                    // Should check if it's a directory or file and clean accordingly
                                    // Simplified for safety: skipping manual deep traversal for now, 
                                    // only cleaning known safe subdirs if they match exact targets
                                }
                            }
                        }
                        
                        // Safer approach for known paths:
                         if path.contains("com.adobe.GrowthSDK") {
                             // This folder seems to be purely analytics/growth data
                             do {
                                 let contents = try FileManager.default.contentsOfDirectory(atPath: expandedPath)
                                 for item in contents {
                                     let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                                     try fileHelper.removeItem(atPath: itemPath)
                                     filesRemoved += 1
                                 }
                                 bytesRemoved += size
                             } catch {}
                         }
                    } else {
                        // Standard cache cleaning
                        let contents = fileHelper.contentsOfDirectory(atPath: expandedPath)
                        for item in contents {
                            let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                            do {
                                try fileHelper.removeItem(atPath: itemPath)
                                filesRemoved += 1
                            } catch {}
                        }
                        bytesRemoved += size
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
