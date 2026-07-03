import Combine
import Foundation

protocol CleaningService {
    var category: CleaningCategory { get }

    func scan(progress: ((String) -> Void)?) async -> ScanResult
    func clean() async -> CleaningResult
}

class BaseCleaningService {
    let fileHelper = FileSystemHelper.shared
    let shell = ShellExecutor.shared
}
