import Combine
import Foundation

protocol CleaningService: Sendable {
    var category: CleaningCategory { get }

    func scan(progress: (@Sendable (String) -> Void)?) async -> ScanResult
    func clean() async -> CleaningResult
}

class BaseCleaningService: @unchecked Sendable {
    let fileHelper = FileSystemHelper.shared
    let shell = ShellExecutor.shared
}
