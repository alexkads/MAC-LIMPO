import Foundation

/// Remove patches superados de SDKs, runtimes e targeting packs do .NET,
/// preservando sempre o mais novo de cada linha. Instalações via `.pkg` da
/// Microsoft ficam em `/usr/local/share/dotnet` (root); as do `dotnet-install`
/// ficam em `~/.dotnet` (usuário). As duas são varridas.
///
/// Regras de retenção (uma diferente por tipo de pasta, porque o roll-forward
/// do .NET é diferente para cada uma):
///
/// - **SDKs** (`sdk/6.0.421`): o `global.json` padrão (`rollForward:
///   latestPatch`) só aceita SDKs do mesmo *feature band* (as centenas do
///   patch: 6.0.4xx). Por isso o mais novo de cada `major.minor.band` fica.
/// - **Runtimes e packs** (`shared/Microsoft.NETCore.App/6.0.29`,
///   `packs/Microsoft.NETCore.App.Ref/6.0.29`): apps rodam no patch mais novo
///   do mesmo `major.minor`, então o mais novo de cada `major.minor` fica.
///
/// Só versões estáveis `X.Y.Z` entram; previews (`10.0.100-rc.1`) ficam
/// intocados — geralmente são a única cópia daquela linha.
///
/// **Modo agressivo** (decisão do usuário, porque reinstalar custa downloads):
/// - SDKs de majors fora de suporte (6, 7…) e, nos demais, só o mais novo de
///   cada `major.minor` fica (9.0.102 sai se houver 9.0.306). O SDK mais novo
///   instalado e a banda fixada por qualquer `global.json` nunca saem.
/// - Workloads (MAUI, Android, iOS, Aspire…) que nenhum projeto usa —
///   costumam ser a maior parte de `packs/`. Desinstalados pelo próprio
///   `dotnet workload uninstall`, que também recolhe os packs.
final class DotnetSdkCleaningService: BaseCleaningService, CleaningService, @unchecked Sendable {
    let category: CleaningCategory = .dotnetSdks

    /// Raízes de instalação do .NET. Cada uma tem a mesma estrutura interna.
    private let installRoots = [
        "/usr/local/share/dotnet",
        "~/.dotnet"
    ]

    /// Pastas versionadas dentro de uma raiz e a regra de retenção de cada uma.
    /// Packs de workloads (iOS, Android, MAUI) NÃO entram: a versão deles é
    /// escolhida pelo manifest do workload, não por roll-forward.
    private static let versionedDirs: [(relative: String, rule: RetentionRule)] = [
        ("sdk", .featureBand),
        ("shared/Microsoft.NETCore.App", .minor),
        ("shared/Microsoft.AspNetCore.App", .minor),
        ("shared/Microsoft.WindowsDesktop.App", .minor),
        ("packs/Microsoft.NETCore.App.Ref", .minor),
        ("packs/Microsoft.AspNetCore.App.Ref", .minor),
        ("packs/Microsoft.WindowsDesktop.App.Ref", .minor),
        ("packs/Microsoft.NETCore.App.Host.osx-arm64", .minor),
        ("packs/Microsoft.NETCore.App.Host.osx-x64", .minor),
        ("templates", .minor)
    ]

    enum RetentionRule {
        /// Mantém o mais novo de cada `major.minor.<centena do patch>`.
        case featureBand
        /// Mantém o mais novo de cada `major.minor`.
        case minor
    }

    /// Um item versionado candidato à remoção.
    struct Candidate {
        let path: String
        let label: String
        let size: Int64
        /// Pertence ao root (precisa de senha de admin para remover).
        let requiresAdmin: Bool
    }

    // MARK: - Regras puras (testáveis)

    /// Divide "6.0.421" em [6, 0, 421]. Devolve `nil` para previews ou nomes
    /// que não são versão (ex.: "NuGetFallbackFolder").
    static func stableVersionNumbers(_ name: String) -> [Int]? {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) else { return nil }
            numbers.append(value)
        }
        return numbers
    }

    /// Chave de agrupamento de acordo com a regra.
    private static func groupKey(_ numbers: [Int], rule: RetentionRule) -> String {
        switch rule {
        case .featureBand:
            "\(numbers[0]).\(numbers[1]).\(numbers[2] / 100)"
        case .minor:
            "\(numbers[0]).\(numbers[1])"
        }
    }

    /// Dado um conjunto de nomes de pasta versionados, devolve os que podem ser
    /// removidos: todos menos o mais novo de cada grupo. Nomes que não são
    /// versão estável são ignorados (nunca removidos).
    static func obsoleteVersions(among names: [String], rule: RetentionRule) -> [String] {
        var newest: [String: (name: String, numbers: [Int])] = [:]
        var versioned: [(name: String, numbers: [Int])] = []

        for name in names {
            guard let numbers = stableVersionNumbers(name) else { continue }
            versioned.append((name, numbers))
            let key = groupKey(numbers, rule: rule)
            if let current = newest[key], !current.numbers.lexicographicallyPrecedes(numbers) {
                continue
            }
            newest[key] = (name, numbers)
        }

        let protected = Set(newest.values.map(\.name))
        return versioned.map(\.name).filter { !protected.contains($0) }.sorted {
            (stableVersionNumbers($0) ?? []).lexicographicallyPrecedes(stableVersionNumbers($1) ?? [])
        }
    }

    // MARK: - Modo agressivo: regras puras (testáveis)

    /// Fim do suporte de cada major (dotnet.microsoft.com/platform/support/policy).
    static let endOfSupport: [Int: String] = [
        5: "2022-05-10", 6: "2024-11-12", 7: "2024-05-14", 8: "2026-11-10", 9: "2026-11-10"
    ]

    static func isOutOfSupport(major: Int, on date: Date) -> Bool {
        guard let end = endOfSupport[major] else { return major < 5 }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let endDate = formatter.date(from: end) else { return false }
        return date > endDate
    }

    /// Banda de um SDK ("9.0.306" → "9.0.3").
    static func band(of numbers: [Int]) -> String {
        "\(numbers[0]).\(numbers[1]).\(numbers[2] / 100)"
    }

    /// SDKs a remover no modo agressivo: majors fora de suporte e, nos outros,
    /// tudo menos o mais novo de cada `major.minor`. Ficam sempre o SDK mais
    /// novo instalado e o mais novo de cada banda fixada por um `global.json`.
    static func aggressiveSDKRemovals(among names: [String], pinnedBands: Set<String>, now: Date) -> [String] {
        let versions = names.compactMap { name in stableVersionNumbers(name).map { (name, $0) } }
        guard let newestOverall = versions.max(by: { $0.1.lexicographicallyPrecedes($1.1) }) else { return [] }

        var newestPerMinor: [String: [Int]] = [:]
        var newestPerBand: [String: [Int]] = [:]
        for (_, numbers) in versions {
            let minor = "\(numbers[0]).\(numbers[1])"
            if newestPerMinor[minor].map({ $0.lexicographicallyPrecedes(numbers) }) ?? true { newestPerMinor[minor] = numbers }
            let band = band(of: numbers)
            if newestPerBand[band].map({ $0.lexicographicallyPrecedes(numbers) }) ?? true { newestPerBand[band] = numbers }
        }

        return versions.filter { name, numbers in
            if name == newestOverall.0 { return false }
            let band = band(of: numbers)
            if pinnedBands.contains(band), newestPerBand[band] == numbers { return false }
            if isOutOfSupport(major: numbers[0], on: now) { return true }
            return newestPerMinor["\(numbers[0]).\(numbers[1])"] != numbers
        }
        .map(\.0)
        .sorted { (stableVersionNumbers($0) ?? []).lexicographicallyPrecedes(stableVersionNumbers($1) ?? []) }
    }

    /// O que os projetos do usuário pedem do .NET.
    struct ProjectUsage: Equatable {
        /// Algum projeto mira Android/iOS/Mac Catalyst/macOS/tvOS ou usa MAUI.
        var usesMobile = false
        /// Algum AppHost do Aspire 8 (ainda dependente do workload `aspire`).
        var usesAspireWorkload = false
        /// Bandas fixadas por `global.json` ("10.0.1").
        var pinnedBands: Set<String> = []
    }

    /// Lê um `.csproj`/`.fsproj`/`Directory.Build.props`.
    static func absorb(projectFile contents: String, into usage: inout ProjectUsage) {
        let lower = contents.lowercased()
        let mobileMarkers = ["-android", "-ios", "-maccatalyst", "-macos", "-tvos", "<usemaui>true"]
        if mobileMarkers.contains(where: lower.contains) { usage.usesMobile = true }
        // Aspire 9+ usa o SDK `Aspire.AppHost.Sdk` do NuGet; só o 8 precisa do workload.
        if lower.contains("<isaspirehost>true"), !lower.contains("aspire.apphost.sdk") {
            usage.usesAspireWorkload = true
        }
    }

    /// Lê um `global.json` e registra a banda do SDK fixado.
    static func absorb(globalJSON contents: String, into usage: inout ProjectUsage) {
        guard let data = contents.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sdk = root["sdk"] as? [String: Any],
              let version = sdk["version"] as? String,
              let numbers = stableVersionNumbers(version)
        else { return }
        usage.pinnedBands.insert(band(of: numbers))
    }

    /// Workloads de plataforma móvel/desktop da Apple e Android.
    static let mobileWorkloadPrefixes = ["maui", "android", "ios", "maccatalyst", "macos", "tvos", "mobile-"]

    /// Workloads instalados que os projetos não usam. Workloads desconhecidos
    /// (wasm-tools, …) contam como usados: na dúvida, ficam.
    static func unusedWorkloads(_ installed: [String], usage: ProjectUsage) -> [String] {
        installed.filter { id in
            if id == "aspire" { return !usage.usesAspireWorkload }
            if mobileWorkloadPrefixes.contains(where: { id.hasPrefix($0) }) { return !usage.usesMobile }
            return false
        }.sorted()
    }

    // MARK: - Projetos e workloads (disco)

    /// Pastas onde costumam ficar os projetos.
    private let projectRoots = ["~/Projects", "~/Developer", "~/dev", "~/src", "~/code", "~/repos", "~/workspace", "~/source"]
    private static let skippedFolders: Set<String> = [
        "node_modules", ".git", "bin", "obj", ".build", "target", "Pods", "DerivedData",
        "build", "dist", ".venv", "vendor", ".next", ".nuget"
    ]

    /// Varre os projetos .NET (até 6 níveis) e junta o que eles pedem.
    func projectUsage() -> ProjectUsage {
        var usage = ProjectUsage()
        let manager = FileManager.default
        for root in projectRoots {
            let base = URL(fileURLWithPath: fileHelper.expandPath(root))
            guard let walker = manager.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey],
                                                  options: [.skipsPackageDescendants]) else { continue }
            var visited = 0
            while let url = walker.nextObject() as? URL, visited < 200_000 {
                visited += 1
                let name = url.lastPathComponent
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if Self.skippedFolders.contains(name) || walker.level > 6 { walker.skipDescendants() }
                    continue
                }
                let ext = url.pathExtension.lowercased()
                if ["csproj", "fsproj", "vbproj"].contains(ext) || name == "Directory.Build.props" {
                    if let text = try? String(contentsOf: url, encoding: .utf8) { Self.absorb(projectFile: text, into: &usage) }
                } else if name == "global.json" {
                    if let text = try? String(contentsOf: url, encoding: .utf8) { Self.absorb(globalJSON: text, into: &usage) }
                }
            }
        }
        return usage
    }

    /// Workloads instalados numa raiz, por banda (`metadata/workloads/<banda>/InstalledWorkloads`).
    private func installedWorkloads(in root: String) -> [(band: String, ids: [String])] {
        let base = (root as NSString).appendingPathComponent("metadata/workloads")
        return fileHelper.contentsOfDirectory(atPath: base).compactMap { band in
            guard Self.stableVersionNumbers(band) != nil else { return nil }
            let dir = (base as NSString).appendingPathComponent("\(band)/InstalledWorkloads")
            let ids = fileHelper.contentsOfDirectory(atPath: dir).filter { $0.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil }
            return ids.isEmpty ? nil : (band, ids)
        }
    }

    /// Tamanho dos packs de workload instalados numa raiz (`InstalledPacks/v1`).
    private func workloadPacksSize(in root: String) -> Int64 {
        let records = (root as NSString).appendingPathComponent("metadata/workloads/InstalledPacks/v1")
        return fileHelper.contentsOfDirectory(atPath: records).reduce(Int64(0)) { total, pack in
            let path = (root as NSString).appendingPathComponent("packs/\(pack)")
            return total + (fileHelper.fileExists(atPath: path) ? fileHelper.sizeOfDirectory(atPath: path) : 0)
        }
    }

    /// Plano de workloads de uma raiz: o que sai e quanto libera (o tamanho só é
    /// conhecido quando TODOS os workloads saem — os packs são compartilhados).
    struct WorkloadPlan {
        let root: String
        let band: String
        let ids: [String]
        let estimatedSize: Int64
    }

    func workloadPlans(usage: ProjectUsage) -> [WorkloadPlan] {
        installRoots.flatMap { root -> [WorkloadPlan] in
            let expanded = fileHelper.expandPath(root)
            let installed = installedWorkloads(in: expanded)
            let unusedPerBand = installed.map { ($0.band, Self.unusedWorkloads($0.ids, usage: usage)) }
            let removesAll = installed.allSatisfy { band in
                Self.unusedWorkloads(band.ids, usage: usage).count == band.ids.count
            }
            let packs = removesAll ? workloadPacksSize(in: expanded) : 0
            let bands = unusedPerBand.filter { !$0.1.isEmpty }
            return bands.enumerated().map { offset, entry in
                WorkloadPlan(root: expanded, band: entry.0, ids: entry.1, estimatedSize: offset == 0 ? packs : 0)
            }
        }
    }

    /// Desinstala os workloads com o SDK da banda onde foram instalados (o
    /// `dotnet workload` só enxerga os da sua banda): um `global.json` numa
    /// pasta temporária fixa esse SDK. Depois, `workload clean` recolhe packs
    /// órfãos. Na raiz do sistema roda com senha de admin.
    private func uninstallWorkloads(_ plan: WorkloadPlan, errors: inout [String]) -> Int64 {
        let sdkDir = (plan.root as NSString).appendingPathComponent("sdk")
        guard let bandNumbers = Self.stableVersionNumbers(plan.band) else { return 0 }
        let bandKey = Self.band(of: bandNumbers)
        let sdk = fileHelper.contentsOfDirectory(atPath: sdkDir)
            .compactMap { name in Self.stableVersionNumbers(name).map { (name, $0) } }
            .filter { Self.band(of: $0.1) == bandKey }
            .max { $0.1.lexicographicallyPrecedes($1.1) }?.0
        guard let sdk else {
            errors.append("No .NET SDK \(plan.band) left to uninstall workloads \(plan.ids.joined(separator: ", "))")
            return 0
        }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("maclimpo-dotnet-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let globalJSON = #"{"sdk":{"version":"\#(sdk)","rollForward":"disable"}}"#
        try? globalJSON.write(to: work.appendingPathComponent("global.json"), atomically: true, encoding: .utf8)

        let before = workloadPacksSize(in: plan.root)
        let dotnet = (plan.root as NSString).appendingPathComponent("dotnet")
        let environment = "DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1"
        let command = "cd '\(work.path)' && \(environment) '\(dotnet)' workload uninstall \(plan.ids.joined(separator: " ")) " +
            "&& \(environment) '\(dotnet)' workload clean"

        let result: (output: String, error: String, exitCode: Int32)
        if FileManager.default.isWritableFile(atPath: plan.root) {
            result = shell.execute(command, timeout: 900)
        } else {
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = "do shell script \"\(escaped)\" with administrator privileges"
            result = shell.run("/usr/bin/osascript", ["-e", script], timeout: 900)
        }
        if result.exitCode != 0 {
            if result.error.contains("User canceled") {
                logger.log("Senha cancelada; workloads .NET mantidos", level: .info)
            } else {
                errors.append("Failed to uninstall .NET workloads: \(plan.ids.joined(separator: ", "))")
                logger.log("dotnet workload uninstall falhou: \(result.error)", level: .error)
            }
            return 0
        }
        logger.log("Workloads .NET removidos: \(plan.ids.joined(separator: ", "))", level: .info)
        return max(0, before - workloadPacksSize(in: plan.root))
    }

    // MARK: - Inventário

    /// Lista tudo que seria removido nas raízes instaladas. Com `aggressive`, os
    /// SDKs seguem `aggressiveSDKRemovals` (um superconjunto da regra padrão).
    func candidates(aggressive: Bool = false, usage: ProjectUsage = ProjectUsage()) -> [Candidate] {
        var result: [Candidate] = []
        for root in installRoots {
            let expandedRoot = fileHelper.expandPath(root)
            guard fileHelper.fileExists(atPath: expandedRoot) else { continue }

            for entry in Self.versionedDirs {
                let dir = (expandedRoot as NSString).appendingPathComponent(entry.relative)
                guard fileHelper.fileExists(atPath: dir) else { continue }

                let names = fileHelper.contentsOfDirectory(atPath: dir)
                let versions = aggressive && entry.rule == .featureBand
                    ? Self.aggressiveSDKRemovals(among: names, pinnedBands: usage.pinnedBands, now: Date())
                    : Self.obsoleteVersions(among: names, rule: entry.rule)
                for version in versions {
                    let path = (dir as NSString).appendingPathComponent(version)
                    result.append(Candidate(
                        path: path,
                        label: "\((entry.relative as NSString).lastPathComponent) \(version)",
                        size: fileHelper.sizeOfDirectory(atPath: path),
                        requiresAdmin: !FileManager.default.isWritableFile(atPath: dir)
                    ))
                }
            }
        }
        return result
    }

    // MARK: - Scan

    func scan(progress: (@Sendable (String) -> Void)?) async -> ScanResult {
        progress?("Scanning .NET SDKs...")
        logger.log("Iniciando escaneamento de SDKs .NET", level: .info)

        let aggressive = CleaningOptions.shared.aggressiveMode
        progress?("Reading .NET projects...")
        let usage = projectUsage()
        let found = candidates(aggressive: aggressive, usage: usage)
        var items: [String] = []
        var totalSize: Int64 = 0

        // Agrupa por pasta (sdk, runtime, pack) para o relatório não virar uma
        // lista de 40 linhas.
        var byKind: [String: (count: Int, size: Int64)] = [:]
        var order: [String] = []
        for candidate in found {
            let kind = ((candidate.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
            if byKind[kind] == nil { order.append(kind) }
            byKind[kind, default: (0, 0)].count += 1
            byKind[kind, default: (0, 0)].size += candidate.size
            totalSize += candidate.size
        }
        for kind in order {
            let entry = byKind[kind]!
            items.append("\(kind): \(entry.count) superseded (\(fileHelper.formatBytes(entry.size)))")
        }

        // Workloads sem uso e, fora do modo agressivo, o que ele removeria a mais.
        let plans = workloadPlans(usage: usage)
        let workloadBytes = plans.reduce(Int64(0)) { $0 + $1.estimatedSize }
        let suffix = aggressive ? "" : " (aggressive mode only)"
        for plan in plans {
            let size = plan.estimatedSize > 0 ? ": \(fileHelper.formatBytes(plan.estimatedSize))" : ""
            items.append("Unused workloads \(plan.ids.joined(separator: ", ")) — no project targets them\(size)\(suffix)")
        }
        if aggressive {
            totalSize += workloadBytes
        } else {
            let defaultPaths = Set(found.map(\.path))
            let extra = candidates(aggressive: true, usage: usage).filter { !defaultPaths.contains($0.path) }
            if !extra.isEmpty {
                let bytes = extra.reduce(Int64(0)) { $0 + $1.size }
                let names = extra.map(\.label).joined(separator: ", ")
                items.append("Out-of-support or superseded \(names): \(fileHelper.formatBytes(bytes)) (aggressive mode only)")
            }
        }
        if found.contains(where: \.requiresAdmin) || (aggressive && !plans.isEmpty) {
            items.append("Requires admin password (system-wide install)")
        }

        logger.log("Escaneamento .NET concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        return ScanResult(category: category, estimatedSize: totalSize, itemCount: items.count, items: items)
    }

    // MARK: - Clean

    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []

        logger.log("Iniciando limpeza de SDKs .NET", level: .info)
        let aggressive = CleaningOptions.shared.aggressiveMode
        let usage = projectUsage()

        // 0. Workloads primeiro: a desinstalação precisa do SDK da banda deles,
        //    que a etapa seguinte pode remover.
        if aggressive {
            for plan in workloadPlans(usage: usage) {
                let freed = uninstallWorkloads(plan, errors: &errors)
                bytesRemoved += freed
                if freed > 0 { filesRemoved += plan.ids.count }
            }
        }

        let found = candidates(aggressive: aggressive, usage: usage)

        // 1. Itens do usuário (~/.dotnet): Lixeira primeiro, remoção direta como fallback.
        for candidate in found where !candidate.requiresAdmin {
            if fileHelper.trashItem(atPath: candidate.path) {
                bytesRemoved += candidate.size
                filesRemoved += 1
                continue
            }
            do {
                try fileHelper.removeItem(atPath: candidate.path)
                bytesRemoved += candidate.size
                filesRemoved += 1
            } catch {
                errors.append("Failed to remove \(candidate.label)")
                logger.log("Falha ao remover: \(candidate.path)", level: .error)
            }
        }

        // 2. Itens root-owned (/usr/local/share/dotnet): um único
        //    `do shell script … with administrator privileges`, ou seja, uma
        //    senha só. Os paths vêm de constantes do código + nomes de pasta
        //    validados como versão numérica, nunca de entrada do usuário.
        let adminItems = found.filter(\.requiresAdmin)
        if !adminItems.isEmpty {
            let quoted = adminItems.map { "\\\"\($0.path)\\\"" }.joined(separator: " ")
            let appleScript = """
            do shell script "rm -rf \(quoted)" with administrator privileges
            """
            let result = shell.execute("osascript -e '\(appleScript)'", timeout: 300)
            if result.exitCode == 0 {
                bytesRemoved += adminItems.reduce(0) { $0 + $1.size }
                filesRemoved += adminItems.count
                logger.log("SDKs .NET root-owned removidos (\(adminItems.count) itens)", level: .info)
            } else if result.error.contains("User canceled") {
                logger.log("Usuário cancelou o pedido de senha; SDKs do sistema mantidos", level: .info)
            } else {
                errors.append("Failed to remove system-wide .NET SDKs")
                logger.log("osascript falhou: \(result.error)", level: .error)
            }
        }

        logger.log("Limpeza .NET concluída: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)
        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: Date().timeIntervalSince(startTime),
            success: errors.isEmpty
        )
    }
}
