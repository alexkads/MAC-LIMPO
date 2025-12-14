import Foundation

class LargeFilesCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .largeFiles
    
    private let minimumFileSize: Int64 = 500_000_000 // 500MB
    private let searchPaths = [
        "~/Documents",
        "~/Downloads",
        "~/Desktop",
        "~/Movies"
    ]
    
    private var foundFiles: [(path: String, size: Int64)] = []
    
    func scan() async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        foundFiles.removeAll()
        
        for path in searchPaths {
            let expandedPath = fileHelper.expandPath(path)
            await findLargeFiles(inPath: expandedPath)
        }
        
        // Ordena por tamanho (maior primeiro)
        foundFiles.sort { $0.size > $1.size }
        
        for file in foundFiles.prefix(20) {
            totalSize += file.size
            let fileName = (file.path as NSString).lastPathComponent
            items.append("\(fileName): \(fileHelper.formatBytes(file.size))")
        }
        
        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: foundFiles.count,
            items: items
        )
    }
    
    private func findLargeFiles(inPath path: String) async {
        guard fileHelper.fileExists(atPath: path) else { return }
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: path) else { return }
        
        while let file = enumerator.nextObject() as? String {
            let filePath = (path as NSString).appendingPathComponent(file)
            
            do {
                let attributes = try fileManager.attributesOfItem(atPath: filePath)
                
                // Verifica se é um arquivo (não diretório)
                if let fileType = attributes[.type] as? FileAttributeType,
                   fileType == .typeRegular,
                   let fileSize = attributes[.size] as? Int64 {
                    
                    if fileSize >= minimumFileSize {
                        foundFiles.append((path: filePath, size: fileSize))
                    }
                }
            } catch {
                // Ignora erros de permissão
                continue
            }
        }
    }
    
    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []
        
        // Nota: Este serviço apenas identifica arquivos grandes
        // Não remove automaticamente por segurança
        // O usuário deve revisar manualmente
        
        errors.append("Large files found but not removed automatically for safety")
        errors.append("Please review the list and manually delete unwanted files")
        
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
