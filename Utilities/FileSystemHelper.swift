import Foundation
import os.log

class FileSystemHelper {
    static let shared = FileSystemHelper()
    private let fileManager = FileManager.default
    
    // Calcula o tamanho de um diretório recursivamente
    func sizeOfDirectory(atPath path: String) -> Int64 {
        guard fileManager.fileExists(atPath: path) else { return 0 }
        
        var totalSize: Int64 = 0
        
        if let enumerator = fileManager.enumerator(atPath: path) {
            while let file = enumerator.nextObject() as? String {
                let filePath = (path as NSString).appendingPathComponent(file)
                
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: filePath)
                    if let fileSize = attributes[.size] as? Int64 {
                        totalSize += fileSize
                    }
                } catch {
                    // Ignora erros de permissão
                    continue
                }
            }
        }
        
        return totalSize
    }
    
    // Remove diretório ou arquivo
    func removeItem(atPath path: String) throws {
        try fileManager.removeItem(atPath: path)
    }
    
    // Lista conteúdo de diretório
    func contentsOfDirectory(atPath path: String) -> [String] {
        do {
            return try fileManager.contentsOfDirectory(atPath: path)
        } catch {
            return []
        }
    }
    
    // Verifica se path existe
    func fileExists(atPath path: String) -> Bool {
        return fileManager.fileExists(atPath: path)
    }
    
    // Expande ~ para home directory
    func expandPath(_ path: String) -> String {
        return (path as NSString).expandingTildeInPath
    }
    
    // Obtém espaço disponível em disco
    func availableDiskSpace() -> Int64 {
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSize = systemAttributes[.systemFreeSize] as? Int64 {
                return freeSize
            }
        } catch {
            return 0
        }
        return 0
    }
    
    // Obtém tamanho total do disco
    func totalDiskSpace() -> Int64 {
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let totalSize = systemAttributes[.systemSize] as? Int64 {
                return totalSize
            }
        } catch {
            return 0
        }
        return 0
    }
    
    // Formata bytes para string legível
    func formatBytes(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    // Conta arquivos em diretório
    func countFiles(inDirectory path: String) -> Int {
        var count = 0
        if let enumerator = fileManager.enumerator(atPath: path) {
            while enumerator.nextObject() != nil {
                count += 1
            }
        }
        return count
    }
}

// MARK: - Logger

/// Sistema de logging profissional usando Unified Logging do macOS
class Logger {
    static let shared = Logger()
    
    private let subsystem = Bundle.main.bundleIdentifier ?? "com.maclimpo.app"
    private let log: OSLog
    
    private init() {
        self.log = OSLog(subsystem: subsystem, category: "general")
    }
    
    // MARK: - Log Levels
    
    /// Log de debug (apenas em DEBUG builds)
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        os_log(.debug, log: log, "%{public}@:%d %{public}@ - %{public}@", fileName, line, function, message)
        #endif
    }
    
    /// Log de informação
    func info(_ message: String) {
        os_log(.info, log: log, "%{public}@", message)
    }
    
    /// Log de aviso
    func warning(_ message: String) {
        os_log(.default, log: log, "⚠️ %{public}@", message)
    }
    
    /// Log de erro
    func error(_ message: String, error: Error? = nil) {
        if let error = error {
            os_log(.error, log: log, "❌ %{public}@: %{public}@", message, error.localizedDescription)
        } else {
            os_log(.error, log: log, "❌ %{public}@", message)
        }
    }
    
    /// Log de sucesso
    func success(_ message: String) {
        os_log(.info, log: log, "✅ %{public}@", message)
    }
    
    // MARK: - Logs com Categoria
    
    /// Log de scan
    func scan(category: String, message: String) {
        os_log(.info, log: log, "🔍 [%{public}@] %{public}@", category, message)
    }
    
    /// Log de limpeza
    func clean(category: String, message: String) {
        os_log(.info, log: log, "🧹 [%{public}@] %{public}@", category, message)
    }
}
