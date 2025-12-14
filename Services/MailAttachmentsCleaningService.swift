import Foundation

class MailAttachmentsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .mailAttachments
    
    private let mailPaths = [
        "~/Library/Mail/V*/MailData/Attachments",
        "~/Library/Mail Downloads"
    ]
    
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
    
    func scan() async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for path in mailPaths {
            for resolvedPath in resolvePaths(path) {
                if fileHelper.fileExists(atPath: resolvedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: resolvedPath)
                    if size > 0 {
                        totalSize += size
                        let pathName = (resolvedPath as NSString).lastPathComponent
                        items.append("\(pathName): \(fileHelper.formatBytes(size))")
                    }
                }
            }
        }
        
        if items.isEmpty {
            items.append("No Mail attachments cache found")
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
        
        // Limpa apenas Mail Downloads (seguro)
        let downloadsPath = fileHelper.expandPath("~/Library/Mail Downloads")
        
        if fileHelper.fileExists(atPath: downloadsPath) {
            let size = fileHelper.sizeOfDirectory(atPath: downloadsPath)
            let contents = fileHelper.contentsOfDirectory(atPath: downloadsPath)
            
            for item in contents {
                let itemPath = (downloadsPath as NSString).appendingPathComponent(item)
                do {
                    try fileHelper.removeItem(atPath: itemPath)
                    filesRemoved += 1
                } catch {
                    errors.append("Failed to remove \(item): \(error.localizedDescription)")
                }
            }
            
            bytesRemoved += size
        }
        
        // Nota: Não limpa attachments da pasta Mail/MailData pois
        // pode quebrar referências de emails
        errors.append("Only Mail Downloads cleared for safety")
        errors.append("Attachments in Mail database preserved")
        
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
