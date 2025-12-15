import Foundation
import AppKit

class TrashCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .trash
    
    private let trashPath = "~/.Trash"
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var itemCount = 0
        
        let expandedPath = fileHelper.expandPath(trashPath)
        if fileHelper.fileExists(atPath: expandedPath) {
            totalSize = fileHelper.sizeOfDirectory(atPath: expandedPath)
            itemCount = fileHelper.contentsOfDirectory(atPath: expandedPath).count
        }
        
        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: itemCount,
            items: ["\(itemCount) items in Trash"]
        )
    }
    
    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []
        
        let expandedPath = fileHelper.expandPath(trashPath)
        
        // Obtém tamanho antes de esvaziar
        if fileHelper.fileExists(atPath: expandedPath) {
            bytesRemoved = fileHelper.sizeOfDirectory(atPath: expandedPath)
            filesRemoved = fileHelper.contentsOfDirectory(atPath: expandedPath).count
        }
        
        // Usa NSWorkspace para esvaziar a lixeira de forma segura
        await MainActor.run {
            do {
                let url = URL(fileURLWithPath: expandedPath)
                let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                
                for itemURL in contents {
                    try FileManager.default.removeItem(at: itemURL)
                }
            } catch {
                errors.append("Failed to empty trash: \(error.localizedDescription)")
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
