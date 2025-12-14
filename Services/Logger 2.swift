import Foundation
import os.log

/// Helper para logging consistente em toda a aplicação
/// Usa o sistema de Unified Logging do macOS para melhor performance e filtragem
class Logger {
    static let shared = Logger()
    
    private let subsystem = Bundle.main.bundleIdentifier ?? "com.maclimpo.app"
    private let log: OSLog
    
    private init() {
        self.log = OSLog(subsystem: subsystem, category: "general")
    }
    
    // MARK: - Log Levels
    
    /// Log de debug (apenas desenvolvimento)
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        os_log(.debug, log: log, "%{public}@:%d %{public}@ - %{public}@", fileName, line, function, message)
        #endif
    }
    
    /// Log de informação (geral)
    func info(_ message: String) {
        os_log(.info, log: log, "%{public}@", message)
    }
    
    /// Log de aviso (não crítico)
    func warning(_ message: String) {
        os_log(.default, log: log, "⚠️ %{public}@", message)
    }
    
    /// Log de erro (crítico)
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
    
    // MARK: - Categoria específica
    
    /// Log de scan de categoria
    func scan(category: String, message: String) {
        os_log(.info, log: log, "🔍 [%{public}@] %{public}@", category, message)
    }
    
    /// Log de limpeza de categoria
    func clean(category: String, message: String) {
        os_log(.info, log: log, "🧹 [%{public}@] %{public}@", category, message)
    }
}
