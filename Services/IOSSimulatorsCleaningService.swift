import Foundation

class IOSSimulatorsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .iosSimulators
    
    func scan() async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        // Obtém lista de simuladores não disponíveis
        let result = shell.execute("xcrun simctl list devices unavailable")
        if result.exitCode == 0 {
            let lines = result.output.components(separatedBy: "\n")
            let deviceLines = lines.filter { $0.contains("(") && $0.contains(")") }
            items.append("\(deviceLines.count) unavailable simulators")
        }
        
        // Tamanho dos dados dos simuladores
        let simulatorsPath = fileHelper.expandPath("~/Library/Developer/CoreSimulator/Devices")
        if fileHelper.fileExists(atPath: simulatorsPath) {
            totalSize = fileHelper.sizeOfDirectory(atPath: simulatorsPath)
        }
        
        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: items.count,
            items: items
        )
    }
    
    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []
        
        // Obtém tamanho antes
        let simulatorsPath = fileHelper.expandPath("~/Library/Developer/CoreSimulator/Devices")
        let sizeBefore = fileHelper.sizeOfDirectory(atPath: simulatorsPath)
        
        // Remove simuladores não disponíveis
        let unavailableResult = shell.execute("xcrun simctl delete unavailable", timeout: 120)
        if unavailableResult.exitCode != 0 {
            errors.append("Failed to delete unavailable simulators: \(unavailableResult.error)")
        }
        
        // Limpa dados dos simuladores (mantém os simuladores)
        let eraseResult = shell.execute("xcrun simctl erase all", timeout: 120)
        if eraseResult.exitCode != 0 {
            errors.append("Failed to erase simulator data: \(eraseResult.error)")
        }
        
        // Calcula espaço liberado
        let sizeAfter = fileHelper.sizeOfDirectory(atPath: simulatorsPath)
        bytesRemoved = max(0, sizeBefore - sizeAfter)
        filesRemoved = 1 // Conta como 1 operação
        
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
