import Foundation
import Combine

protocol CleaningService {
    var category: CleaningCategory { get }
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult
    func clean() async -> CleaningResult
}

class BaseCleaningService {
    let fileHelper = FileSystemHelper.shared
    let shell = ShellExecutor.shared
    
    func measureExecutionTime(_ operation: () async throws -> Void) async -> TimeInterval {
        let start = Date()
        try? await operation()
        return Date().timeIntervalSince(start)
    }
}
