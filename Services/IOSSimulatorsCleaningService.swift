import Foundation

class IOSSimulatorsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .iosSimulators

    /// Runtime de simulador instalado como disk image (simctl). Os runtimes
    /// vivem em /Library/Developer/CoreSimulator (Volumes/Cryptex) e um antigo
    /// pode ocupar 15+ GB.
    struct SimulatorRuntime {
        let identifier: String
        let platform: String
        let version: String
        let sizeBytes: Int64
        let deletable: Bool
    }

    func scan(progress _: ((String) -> Void)?) async -> ScanResult {
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

        // Runtimes antigos (o mais novo de cada plataforma fica; remoção só no
        // modo agressivo porque re-baixar um runtime custa vários GB)
        let obsolete = obsoleteRuntimes()
        if !obsolete.isEmpty {
            let size = obsolete.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let names = obsolete.map { "\($0.platform) \($0.version)" }.joined(separator: ", ")
            if CleaningOptions.shared.aggressiveMode {
                totalSize += size
                items.append("Old runtimes (\(names)): \(fileHelper.formatBytes(size))")
            } else {
                items.append("Old runtimes (\(names)): \(fileHelper.formatBytes(size)) (aggressive mode only)")
            }
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

        // Remove runtimes antigos (só no modo agressivo). O simctl fala com o
        // simdiskimaged, então não precisa de sudo para um usuário admin.
        if CleaningOptions.shared.aggressiveMode {
            for runtime in obsoleteRuntimes() {
                let deleteResult = shell.execute(
                    "xcrun simctl runtime delete \(runtime.identifier)",
                    timeout: 120
                )
                if deleteResult.exitCode == 0 {
                    bytesRemoved += runtime.sizeBytes
                    filesRemoved += 1
                    logger.log(
                        "Runtime removido: \(runtime.platform) \(runtime.version) " +
                            "(\(fileHelper.formatBytes(runtime.sizeBytes)))",
                        level: .info
                    )
                } else {
                    errors.append("Failed to delete runtime \(runtime.platform) \(runtime.version)")
                }
            }
        }

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

    // MARK: - Runtimes

    private func obsoleteRuntimes() -> [SimulatorRuntime] {
        let result = shell.execute("xcrun simctl runtime list -j", timeout: 30)
        guard result.exitCode == 0 else { return [] }
        return Self.obsoleteRuntimes(fromJSON: result.output)
    }

    /// Interpreta o JSON de `simctl runtime list -j` (dicionário UDID → info) e
    /// devolve os runtimes deletáveis que não são o mais novo da sua plataforma.
    static func obsoleteRuntimes(fromJSON json: String) -> [SimulatorRuntime] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { return [] }

        var runtimes: [SimulatorRuntime] = []
        for (identifier, info) in dict {
            guard let version = info["version"] as? String else { continue }
            // "com.apple.CoreSimulator.SimRuntime.iOS-18-3" → "iOS"
            let runtimeId = info["runtimeIdentifier"] as? String ?? ""
            let platform = runtimeId.components(separatedBy: ".").last?
                .components(separatedBy: "-").first
                ?? (info["platformIdentifier"] as? String ?? "unknown")
            runtimes.append(SimulatorRuntime(
                identifier: identifier,
                platform: platform,
                version: version,
                sizeBytes: (info["sizeBytes"] as? NSNumber)?.int64Value ?? 0,
                deletable: info["deletable"] as? Bool ?? true
            ))
        }

        /// Mais novo de cada plataforma (comparação numérica por componente)
        func numbers(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0) ?? 0 }
        }
        var newest: [String: SimulatorRuntime] = [:]
        for runtime in runtimes {
            if let current = newest[runtime.platform],
               numbers(runtime.version).lexicographicallyPrecedes(numbers(current.version))
            {
                continue
            }
            newest[runtime.platform] = runtime
        }

        return runtimes
            .filter(\.deletable)
            .filter { newest[$0.platform]?.identifier != $0.identifier }
            .sorted { $0.version < $1.version }
    }
}
