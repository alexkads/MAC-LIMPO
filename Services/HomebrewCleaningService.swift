import Foundation

/// Homebrew: cache de downloads (Lixeira), `brew cleanup --prune=all` (versões
/// antigas no Cellar, downloads velhos, links quebrados) e `brew autoremove`
/// (dependências que nenhuma fórmula usa mais). Ferramentas grandes que você
/// instalou e das quais nada depende são só listadas — removê-las é decisão sua.
final class HomebrewCleaningService: BaseCleaningService, CleaningService, @unchecked Sendable {
    let category: CleaningCategory = .homebrew

    private let cache = PathBasedCleaningService(category: .homebrew, targets: [
        CleanTarget("~/Library/Caches/Homebrew", label: "Homebrew cache")
    ])

    /// Fórmulas pedidas por você a partir deste tamanho entram na lista informativa.
    private static let largeLeafThreshold: Int64 = 300 * 1024 * 1024
    private static let environment = "HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1"

    // MARK: - Parsing (testável)

    /// "This operation would free approximately 1.2GB of disk space." → bytes.
    /// O Homebrew usa unidades binárias com sufixo curto (KB, MB, GB).
    static func freedBytes(fromCleanupOutput output: String) -> Int64 {
        guard let range = output.range(of: #"free approximately ([0-9.]+)\s*([KMGT]?B)"#, options: .regularExpression)
        else { return 0 }
        let match = String(output[range])
        let parts = match.replacingOccurrences(of: "free approximately", with: "")
            .trimmingCharacters(in: .whitespaces)
        let number = Double(parts.prefix { $0.isNumber || $0 == "." }) ?? 0
        let unit = parts.drop { $0.isNumber || $0 == "." }.trimmingCharacters(in: .whitespaces)
        let multiplier: Double = switch unit {
        case "KB": 1024
        case "MB": 1024 * 1024
        case "GB": 1024 * 1024 * 1024
        case "TB": 1024 * 1024 * 1024 * 1024
        default: 1
        }
        return Int64(number * multiplier)
    }

    /// Links quebrados que o `cleanup` removeria ("Would remove (broken link): …").
    static func brokenLinks(fromCleanupOutput output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .filter { $0.contains("(broken link)") }
            .compactMap { $0.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } }
            .map { ($0 as NSString).lastPathComponent }
    }

    /// Fórmulas que o `autoremove -n` removeria (as linhas depois do cabeçalho "==>").
    static func autoremovable(fromOutput output: String) -> [String] {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let header = lines.firstIndex(where: { $0.hasPrefix("==>") }) else { return [] }
        return lines[(header + 1)...].filter { !$0.isEmpty && !$0.hasPrefix("==>") }
    }

    // MARK: - Inventário

    private var hasBrew: Bool { shell.checkCommandExists("brew") }

    private func brew(_ arguments: String, timeout: TimeInterval = 120) -> (output: String, error: String, exitCode: Int32) {
        shell.execute("\(Self.environment) brew \(arguments)", timeout: timeout)
    }

    private func cellar() -> String? {
        let result = brew("--cellar", timeout: 30)
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !path.isEmpty ? path : nil
    }

    /// Fórmulas instaladas a pedido, das quais nada depende, a partir do limite.
    private func largeLeaves() -> [(name: String, size: Int64)] {
        guard let cellar = cellar() else { return [] }
        let leaves = brew("leaves --installed-on-request", timeout: 60).output
            .split(whereSeparator: \.isNewline).map(String.init)
        return leaves.compactMap { name in
            let size = fileHelper.sizeOfDirectory(atPath: (cellar as NSString).appendingPathComponent(name))
            return size >= Self.largeLeafThreshold ? (name, size) : nil
        }
        .sorted { $0.size > $1.size }
    }

    // MARK: - Scan

    func scan(progress: (@Sendable (String) -> Void)?) async -> ScanResult {
        let cached = await cache.scan(progress: progress)
        var items = cached.items
        var estimated = cached.estimatedSize

        guard await runBlocking({ self.hasBrew }) else {
            return ScanResult(category: category, estimatedSize: estimated, itemCount: items.count, items: items)
        }

        progress?(String(localized: "Checking Homebrew…"))
        let cleanup = await runBlocking { self.brew("cleanup --prune=all -n", timeout: 300).output }
        let cleanupBytes = Self.freedBytes(fromCleanupOutput: cleanup)
        if cleanupBytes > 0 {
            items.append("Old versions and downloads (brew cleanup): \(fileHelper.formatBytes(cleanupBytes))")
            estimated += cleanupBytes
        }
        let links = Self.brokenLinks(fromCleanupOutput: cleanup)
        if !links.isEmpty {
            items.append("\(links.count) broken links: \(links.joined(separator: ", "))")
        }

        let orphans = await runBlocking { Self.autoremovable(fromOutput: self.brew("autoremove -n", timeout: 120).output) }
        if !orphans.isEmpty, let cellar = await runBlocking({ self.cellar() }) {
            let bytes = orphans.reduce(Int64(0)) { $0 + fileHelper.sizeOfDirectory(atPath: (cellar as NSString).appendingPathComponent($1)) }
            items.append("\(orphans.count) unneeded dependencies (brew autoremove): \(fileHelper.formatBytes(bytes))")
            estimated += bytes
        }

        progress?(String(localized: "Measuring Homebrew formulae…"))
        let leaves = await runBlocking { self.largeLeaves() }
        if !leaves.isEmpty {
            items.append("ℹ︎ Large tools you installed that nothing depends on — kept; remove the ones you don't use:")
            for leaf in leaves {
                items.append("    brew uninstall \(leaf.name)  (\(fileHelper.formatBytes(leaf.size)))")
            }
        }

        return ScanResult(category: category, estimatedSize: estimated, itemCount: items.count, items: items)
    }

    // MARK: - Clean

    func clean() async -> CleaningResult {
        let startTime = Date()
        let cached = await cache.clean()
        var bytesRemoved = cached.bytesRemoved
        var filesRemoved = cached.filesRemoved
        var errors = cached.errors

        guard await runBlocking({ self.hasBrew }) else {
            return CleaningResult(category: category, bytesRemoved: bytesRemoved, filesRemoved: filesRemoved,
                                  errors: errors, executionTime: Date().timeIntervalSince(startTime), success: errors.isEmpty)
        }

        // O próprio cleanup diz quanto vai liberar; medir o Cellar inteiro antes
        // e depois custaria mais que a limpeza.
        let preview = await runBlocking { self.brew("cleanup --prune=all -n", timeout: 300).output }
        let cleanup = await runBlocking { self.brew("cleanup --prune=all", timeout: 900) }
        if cleanup.exitCode == 0 {
            bytesRemoved += Self.freedBytes(fromCleanupOutput: preview)
            filesRemoved += preview.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("Would remove") }.count
        } else {
            errors.append(String(localized: "brew cleanup failed: \(String(cleanup.error.prefix(200)))"))
        }

        let orphans = await runBlocking { Self.autoremovable(fromOutput: self.brew("autoremove -n", timeout: 120).output) }
        if !orphans.isEmpty {
            let cellar = await runBlocking { self.cellar() }
            let bytes = orphans.reduce(Int64(0)) { total, name in
                total + (cellar.map { fileHelper.sizeOfDirectory(atPath: ($0 as NSString).appendingPathComponent(name)) } ?? 0)
            }
            let removal = await runBlocking { self.brew("autoremove", timeout: 600) }
            if removal.exitCode == 0 {
                bytesRemoved += bytes
                filesRemoved += orphans.count
            } else {
                errors.append(String(localized: "brew autoremove failed: \(String(removal.error.prefix(200)))"))
            }
        }

        logger.log("Homebrew: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)
        return CleaningResult(category: category, bytesRemoved: bytesRemoved, filesRemoved: filesRemoved,
                              errors: errors, executionTime: Date().timeIntervalSince(startTime), success: errors.isEmpty)
    }
}
