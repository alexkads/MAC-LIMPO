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
final class DotnetSdkCleaningService: BaseCleaningService, CleaningService {
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

    // MARK: - Inventário

    /// Lista tudo que seria removido nas raízes instaladas.
    func candidates() -> [Candidate] {
        var result: [Candidate] = []
        for root in installRoots {
            let expandedRoot = fileHelper.expandPath(root)
            guard fileHelper.fileExists(atPath: expandedRoot) else { continue }

            for entry in Self.versionedDirs {
                let dir = (expandedRoot as NSString).appendingPathComponent(entry.relative)
                guard fileHelper.fileExists(atPath: dir) else { continue }

                let names = fileHelper.contentsOfDirectory(atPath: dir)
                for version in Self.obsoleteVersions(among: names, rule: entry.rule) {
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

    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        progress?("Scanning .NET SDKs...")
        logger.log("Iniciando escaneamento de SDKs .NET", level: .info)

        let found = candidates()
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
        if found.contains(where: \.requiresAdmin) {
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
        let found = candidates()

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
