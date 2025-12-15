import Foundation

class MessagesAttachmentsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .messagesAttachments
    
    private let messagesPaths = [
        "~/Library/Messages/Attachments",
        "~/Library/Messages/Cache"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for path in messagesPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    totalSize += size
                    let pathName = (path as NSString).lastPathComponent
                    items.append("\(pathName): \(fileHelper.formatBytes(size))")
                }
            }
        }
        
        if items.isEmpty {
            items.append("No Messages attachments found")
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
        
        // Limpa apenas o cache, preserva attachments originais
        let cachePath = fileHelper.expandPath("~/Library/Messages/Cache")
        
        if fileHelper.fileExists(atPath: cachePath) {
            let size = fileHelper.sizeOfDirectory(atPath: cachePath)
            let contents = fileHelper.contentsOfDirectory(atPath: cachePath)
            
            for item in contents {
                let itemPath = (cachePath as NSString).appendingPathComponent(item)
                do {
                    try fileHelper.removeItem(atPath: itemPath)
                    filesRemoved += 1
                } catch {
                    errors.append("Failed to remove \(item): \(error.localizedDescription)")
                }
            }
            
            bytesRemoved += size
        }
        
        // Nota sobre attachments
        errors.append("Only Messages cache cleared")
        errors.append("Original attachments preserved to maintain message history")
        
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
