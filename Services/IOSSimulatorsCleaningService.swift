import Foundation

class IOSSimulatorsCleaningService: BaseCleaningService, CleaningService, @unchecked Sendable {
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

    /// Um dispositivo de simulador, como `simctl list devices -j` o descreve.
    struct SimulatorDevice: Equatable {
        let udid: String
        let name: String
        /// "iOS 26.5", derivado da chave do runtime.
        let runtime: String
        let state: String
        let isAvailable: Bool
        /// Tamanho da pasta de dados (o que um `erase` zera), informado pelo próprio simctl.
        let dataSize: Int64

        var isShutdown: Bool { state == "Shutdown" }
        var label: String { "\(name) (\(runtime))" }
    }

    /// O que a limpeza faz com cada dispositivo. Scan e clean usam o mesmo plano,
    /// para o total mostrado no card ser exatamente o que a limpeza tenta liberar.
    struct DevicePlan: Equatable {
        /// Runtime ausente: `simctl delete unavailable` remove o dispositivo inteiro.
        var delete: [SimulatorDevice] = []
        /// Desligados: `simctl erase` zera dados e apps instalados.
        var erase: [SimulatorDevice] = []
        /// Ligados (ou em transição): o `erase` recusa, e apagar mexeria num
        /// simulador em uso. Aparecem na lista, fora do total.
        var inUse: [SimulatorDevice] = []

        var cleanableSize: Int64 { (delete + erase).reduce(0) { $0 + $1.dataSize } }
    }

    /// Runtime baixado pelo MobileAsset que o CoreSimulator não conhece mais
    /// (sobra de um `simctl runtime delete`, que só desregistra). Fica em
    /// /System/Library/AssetsV2, protegido pelo SIP: nem `sudo rm` apaga —
    /// só o `mobileassetd` ou o Terminal da Recuperação.
    struct OrphanRuntimeAsset: Equatable {
        let path: String
        let size: Int64
        /// "iOS 18.3.1 (22D8075)", do Info.plist do asset.
        let label: String
    }

    static let mobileAssetRoot = "/System/Library/AssetsV2"

    func scan(progress _: (@Sendable (String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []

        let plan = await devicePlan()
        totalSize += plan.cleanableSize
        for device in plan.delete {
            items.append("Unavailable \(device.label): \(fileHelper.formatBytes(device.dataSize))")
        }
        for device in plan.erase {
            items.append("Erase \(device.label): \(fileHelper.formatBytes(device.dataSize))")
        }
        for device in plan.inUse {
            items.append(
                "\(device.label): \(fileHelper.formatBytes(device.dataSize)) — in use (\(device.state)), " +
                    "shut it down to clean"
            )
        }

        // Runtimes antigos (o mais novo de cada plataforma fica; remoção só no
        // modo agressivo porque re-baixar um runtime custa vários GB)
        let obsolete = await runBlocking { self.obsoleteRuntimes() }
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

        // Órfãos ficam fora do total: o app não consegue apagá-los (SIP).
        let orphans = await runBlocking { self.orphanRuntimeAssets() }
        if !orphans.isEmpty {
            // Na Recuperação o volume de dados monta com o próprio nome — "Macintosh
            // HD - Data" na instalação padrão, mas pode ser outro ("Data").
            let volume = (try? URL(fileURLWithPath: "/System/Volumes/Data").resourceValues(forKeys: [.volumeNameKey]))?
                .volumeName ?? "Macintosh HD - Data"
            for orphan in orphans {
                items.append("⚠ Orphaned runtime \(orphan.label): \(fileHelper.formatBytes(orphan.size)) " +
                    "— Xcode no longer uses it; macOS protects it (SIP), so remove it from Recovery › Terminal:")
                items.append("    rm -rf \"/Volumes/\(volume)\(orphan.path)\"")
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

        let plan = await devicePlan()

        if !plan.delete.isEmpty {
            let result = await runBlocking { self.shell.execute("xcrun simctl delete unavailable", timeout: 120) }
            if result.exitCode != 0 {
                errors.append(String(localized: "Failed to delete unavailable simulators: \(result.error)"))
            }
        }

        // Um a um, e só os desligados: o antigo `simctl erase all` falhava inteiro
        // (CoreSimulator, código 405) se houvesse qualquer simulador ligado.
        for device in plan.erase {
            let udid = device.udid
            let result = await runBlocking { self.shell.run("/usr/bin/xcrun", ["simctl", "erase", udid], timeout: 120) }
            if result.exitCode != 0 {
                errors.append(String(localized: "Failed to erase \(device.label): \(result.error)"))
            }
        }

        for device in plan.inUse {
            logger.log("Simulador em uso, ignorado: \(device.label) [\(device.state)]", level: .info)
        }

        // Liberado de verdade: tamanho antes menos o que sobrou, pelo próprio simctl.
        // Um dispositivo apagado some da lista e conta inteiro.
        if !(plan.delete + plan.erase).isEmpty {
            let after = await runBlocking { self.listDevices() }
            let remaining = Dictionary(after.map { ($0.udid, $0.dataSize) }, uniquingKeysWith: { first, _ in first })
            for device in plan.delete + plan.erase {
                let freed = max(0, device.dataSize - (remaining[device.udid] ?? 0))
                bytesRemoved += freed
                if freed > 0 { filesRemoved += 1 }
            }
        }

        // Remove runtimes antigos (só no modo agressivo). O simctl fala com o
        // simdiskimaged, então não precisa de sudo para um usuário admin.
        if CleaningOptions.shared.aggressiveMode {
            for runtime in await runBlocking({ self.obsoleteRuntimes() }) {
                let identifier = runtime.identifier
                let deleteResult = await runBlocking {
                    self.shell.run("/usr/bin/xcrun", ["simctl", "runtime", "delete", identifier], timeout: 120)
                }
                if deleteResult.exitCode == 0 {
                    bytesRemoved += runtime.sizeBytes
                    filesRemoved += 1
                    logger.log(
                        "Runtime removido: \(runtime.platform) \(runtime.version) " +
                            "(\(fileHelper.formatBytes(runtime.sizeBytes)))",
                        level: .info
                    )
                } else {
                    errors.append(String(localized: "Failed to delete runtime \(runtime.platform) \(runtime.version)"))
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

    // MARK: - Dispositivos

    private func devicePlan() async -> DevicePlan {
        await runBlocking { Self.plan(for: self.listDevices()) }
    }

    private func listDevices() -> [SimulatorDevice] {
        let result = shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"], timeout: 30)
        guard result.exitCode == 0 else { return [] }
        return Self.devices(fromJSON: result.output)
    }

    /// Interpreta `simctl list devices -j` (`{"devices": {runtimeId: [device]}}`).
    static func devices(fromJSON json: String) -> [SimulatorDevice] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = root["devices"] as? [String: [[String: Any]]]
        else { return [] }

        var devices: [SimulatorDevice] = []
        for (runtimeId, entries) in byRuntime {
            // "com.apple.CoreSimulator.SimRuntime.iOS-26-5" → "iOS 26.5"
            let tail = runtimeId.components(separatedBy: ".").last ?? runtimeId
            let parts = tail.components(separatedBy: "-")
            let runtime = parts.count > 1
                ? "\(parts[0]) \(parts.dropFirst().joined(separator: "."))"
                : tail
            for entry in entries {
                guard let udid = entry["udid"] as? String else { continue }
                devices.append(SimulatorDevice(
                    udid: udid,
                    name: entry["name"] as? String ?? udid,
                    runtime: runtime,
                    state: entry["state"] as? String ?? "Unknown",
                    isAvailable: entry["isAvailable"] as? Bool ?? true,
                    dataSize: (entry["dataPathSize"] as? NSNumber)?.int64Value ?? 0
                ))
            }
        }
        return devices.sorted { $0.dataSize > $1.dataSize }
    }

    /// Decide o destino de cada dispositivo. Função pura (testável).
    static func plan(for devices: [SimulatorDevice]) -> DevicePlan {
        var plan = DevicePlan()
        for device in devices {
            if !device.isAvailable {
                plan.delete.append(device)
            } else if device.isShutdown {
                // Recém-criado ou já zerado: nada a ganhar com erase.
                guard device.dataSize > 0 else { continue }
                plan.erase.append(device)
            } else {
                plan.inUse.append(device)
            }
        }
        return plan
    }

    // MARK: - Runtimes

    /// `.asset` de runtime de simulador em AssetsV2 que nenhum runtime do
    /// `simctl runtime list` usa. Sem resposta do simctl, não aponta nada.
    private func orphanRuntimeAssets() -> [OrphanRuntimeAsset] {
        let result = shell.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"], timeout: 30)
        guard result.exitCode == 0, let registered = Self.registeredImagePaths(fromJSON: result.output) else { return [] }

        let manager = FileManager.default
        let collections = ((try? manager.contentsOfDirectory(atPath: Self.mobileAssetRoot)) ?? [])
            .filter { $0.hasSuffix("SimulatorRuntime") }
        var assets: [String] = []
        for collection in collections {
            let folder = (Self.mobileAssetRoot as NSString).appendingPathComponent(collection)
            for entry in (try? manager.contentsOfDirectory(atPath: folder)) ?? [] where entry.hasSuffix(".asset") {
                assets.append((folder as NSString).appendingPathComponent(entry))
            }
        }

        return Self.orphanAssetPaths(assets, registeredImagePaths: registered).map { path in
            let info = NSDictionary(contentsOfFile: (path as NSString).appendingPathComponent("Info.plist"))
            let properties = info?["MobileAssetProperties"] as? [String: Any]
            let platform = (info?["CFBundleIdentifier"] as? String)?
                .replacingOccurrences(of: "com.apple.MobileAsset.", with: "")
                .replacingOccurrences(of: "SimulatorRuntime", with: "") ?? "Simulator"
            let version = properties?["SimulatorVersion"] as? String ?? "?"
            let build = properties?["Build"] as? String ?? "?"
            return OrphanRuntimeAsset(path: path, size: fileHelper.sizeOfDirectory(atPath: path),
                                      label: "\(platform) \(version) (\(build))")
        }
    }

    /// Caminhos de imagem dos runtimes registrados (`path` de cada entrada de
    /// `simctl runtime list -j`). `nil` se o JSON não for o esperado.
    static func registeredImagePaths(fromJSON json: String) -> [String]? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { return nil }
        return dict.values.compactMap { $0["path"] as? String }
    }

    /// Assets que não contêm a imagem de nenhum runtime registrado. Função pura.
    static func orphanAssetPaths(_ assets: [String], registeredImagePaths: [String]) -> [String] {
        let registered = registeredImagePaths.map { ($0 as NSString).standardizingPath }
        return assets.filter { asset in
            let prefix = (asset as NSString).standardizingPath + "/"
            return !registered.contains { $0 == String(prefix.dropLast()) || $0.hasPrefix(prefix) }
        }.sorted()
    }

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
