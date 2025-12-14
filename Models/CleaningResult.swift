import Foundation

struct CleaningResult {
    var category: CleaningCategory
    var bytesRemoved: Int64
    var filesRemoved: Int
    var errors: [String]
    var executionTime: TimeInterval
    var success: Bool
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: bytesRemoved, countStyle: .file)
    }
    
    init(category: CleaningCategory, bytesRemoved: Int64 = 0, filesRemoved: Int = 0, errors: [String] = [], executionTime: TimeInterval = 0, success: Bool = true) {
        self.category = category
        self.bytesRemoved = bytesRemoved
        self.filesRemoved = filesRemoved
        self.errors = errors
        self.executionTime = executionTime
        self.success = success
    }
}

struct ScanResult {
    var category: CleaningCategory
    var estimatedSize: Int64
    var itemCount: Int
    var items: [String]
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file)
    }
}
