import Foundation
import os.log

/// Níveis de log
enum LogLevel {
    case debug
    case info
    case warning
    case error
}

/// Helper para logging consistente em toda a aplicação
class Logger {
    static let shared = Logger()

    private let subsystem = Bundle.main.bundleIdentifier ?? "com.maclimpo.app"
    private let log: OSLog

    private init() {
        log = OSLog(subsystem: subsystem, category: "general")
    }

    // MARK: - Log genérico com level

    func log(_ message: String, level: LogLevel) {
        switch level {
        case .debug:
            debug(message)
        case .info:
            info(message)
        case .warning:
            warning(message)
        case .error:
            error(message)
        }
    }

    // MARK: - Log Levels

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        os_log(.debug, log: log, "%{public}@:%d %{public}@ - %{public}@", fileName, line, function, message)
    }

    func info(_ message: String) {
        os_log(.info, log: log, "%{public}@", message)
    }

    func warning(_ message: String) {
        os_log(.default, log: log, "⚠️ %{public}@", message)
    }

    func error(_ message: String, error: Error? = nil) {
        if let error {
            os_log(.error, log: log, "❌ %{public}@: %{public}@", message, error.localizedDescription)
        } else {
            os_log(.error, log: log, "❌ %{public}@", message)
        }
    }

    func success(_ message: String) {
        os_log(.info, log: log, "✅ %{public}@", message)
    }

    // MARK: - Categoria específica

    func scan(category: String, message: String) {
        os_log(.info, log: log, "🔍 [%{public}@] %{public}@", category, message)
    }

    func clean(category: String, message: String) {
        os_log(.info, log: log, "🧹 [%{public}@] %{public}@", category, message)
    }
}

/// Logger global para uso em toda a aplicação
let logger = Logger.shared
