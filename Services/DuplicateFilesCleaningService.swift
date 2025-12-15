import Foundation
import CryptoKit

class DuplicateFilesCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .duplicateFiles
    
    private let searchPaths = [
        "~/Documents",
        "~/Downloads",
        "~/Desktop"
    ]
    
    private var duplicates: [String: [String]] = [:] // hash -> [paths]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        duplicates.removeAll()
        
        var fileHashes: [String: String] = [:] // path -> hash
        
        // Procura arquivos e calcula hashes
        for path in searchPaths {
            let expandedPath = fileHelper.expandPath(path)
            await findFiles(inPath: expandedPath, hashes: &fileHashes)
        }
        
        // Identifica duplicados
        var hashToPaths: [String: [String]] = [:]
        for (path, hash) in fileHashes {
            hashToPaths[hash, default: []].append(path)
        }
        
        // Filtra apenas os que têm duplicados
        for (hash, paths) in hashToPaths where paths.count > 1 {
            duplicates[hash] = paths
            
            // Calcula tamanho desperdiçado (todos menos o original)
            if let firstPath = paths.first {
                let size = fileHelper.sizeOfDirectory(atPath: firstPath)
                totalSize += size * Int64(paths.count - 1)
            }
            
            let fileName = (paths[0] as NSString).lastPathComponent
            items.append("\(fileName): \(paths.count) copies")
        }
        
        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: duplicates.count,
            items: Array(items.prefix(15))
        )
    }
    
    private func findFiles(inPath path: String, hashes: inout [String: String]) async {
        guard fileHelper.fileExists(atPath: path) else { return }
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: path) else { return }
        
        while let file = enumerator.nextObject() as? String {
            let filePath = (path as NSString).appendingPathComponent(file)
            
            do {
                let attributes = try fileManager.attributesOfItem(atPath: filePath)
                
                if let fileType = attributes[.type] as? FileAttributeType,
                   fileType == .typeRegular,
                   let fileSize = attributes[.size] as? Int64 {
                    
                    // Apenas arquivos entre 1KB e 100MB para performance
                    if fileSize > 1024 && fileSize < 100_000_000 {
                        if let hash = calculateHash(forFileAt: filePath) {
                            hashes[filePath] = hash
                        }
                    }
                }
            } catch {
                continue
            }
        }
    }
    
    private func calculateHash(forFileAt path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []
        
        // Nota: Arquivos duplicados não são removidos automaticamente
        // por segurança, pois podem ter nomes diferentes mas conteúdo igual
        // propositalmente
        
        errors.append("Duplicate files found but not removed automatically")
        errors.append("Please review and manually delete duplicates if desired")
        
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
