import Foundation

/// Descreve um alvo de limpeza baseado em path para `PathBasedCleaningService`.
struct CleanTarget {
    enum Strategy {
        /// Remove o próprio path (arquivo ou diretório inteiro).
        case removeItem
        /// Preserva o diretório e remove apenas os filhos (útil p/ caches
        /// dentro de pastas que o app espera continuar existindo).
        case removeContents
    }

    let path: String
    /// Rótulo amigável para relatório; default = último componente do path.
    let label: String?
    let strategy: Strategy
    /// Se definido, só considera itens modificados há mais de N dias.
    let olderThanDays: Int?

    init(_ path: String, label: String? = nil, strategy: Strategy = .removeItem, olderThanDays: Int? = nil) {
        self.path = path
        self.label = label
        self.strategy = strategy
        self.olderThanDays = olderThanDays
    }
}

/// Base concreta que implementa `scan`/`clean` uma única vez para os ~25 services
/// que apenas medem e removem uma lista de paths. Subclasses só fornecem os alvos:
///
/// ```swift
/// final class HomebrewCleaningService: PathBasedCleaningService {
///     init() { super.init(category: .homebrew, targets: [CleanTarget("~/Library/Caches/Homebrew")]) }
/// }
/// ```
class PathBasedCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory
    let targets: [CleanTarget]
    /// Se `true` (produção), remoções vão para a Lixeira (reversível). Testes usam
    /// `false` para apagar direto em diretório temporário sem poluir a Lixeira real.
    let useTrash: Bool

    init(category: CleaningCategory, targets: [CleanTarget], useTrash: Bool = true) {
        self.category = category
        self.targets = targets
        self.useTrash = useTrash
    }

    // MARK: - Scan

    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []

        progress?("Scanning \(category.rawValue)...")

        for target in targets {
            let size = measuredSize(of: target)
            if size > 0 {
                totalSize += size
                items.append("\(displayName(for: target)): \(fileHelper.formatBytes(size))")
            }
        }

        logger.log("Scan \(category.rawValue) concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        return ScanResult(category: category, estimatedSize: totalSize, itemCount: items.count, items: items)
    }

    // MARK: - Clean

    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []

        logger.log("Iniciando limpeza de \(category.rawValue)", level: .info)

        for target in targets {
            let expanded = fileHelper.expandPath(target.path)
            guard fileHelper.fileExists(atPath: expanded) else { continue }

            for itemPath in removablePaths(for: target, expanded: expanded) {
                let size = fileHelper.sizeOfDirectory(atPath: itemPath)

                // Preferimos a Lixeira (reversível); só apagamos de vez se a Lixeira falhar.
                if useTrash, fileHelper.trashItem(atPath: itemPath) {
                    bytesRemoved += size
                    filesRemoved += 1
                    continue
                }

                do {
                    try fileHelper.removeItem(atPath: itemPath)
                    bytesRemoved += size
                    filesRemoved += 1
                } catch {
                    errors.append("Falha ao limpar: \(itemPath)")
                    logger.log("Falha ao remover: \(itemPath)", level: .error)
                }
            }
        }

        logger.log(
            "Limpeza \(category.rawValue) concluída: \(fileHelper.formatBytes(bytesRemoved)) liberados",
            level: .info
        )
        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: Date().timeIntervalSince(startTime),
            success: errors.isEmpty
        )
    }

    // MARK: - Helpers (internal p/ testes)

    /// Lista concreta de paths que serão removidos para um alvo, já aplicando
    /// estratégia (item vs conteúdo) e filtro de idade.
    func removablePaths(for target: CleanTarget, expanded: String) -> [String] {
        switch target.strategy {
        case .removeItem:
            if let days = target.olderThanDays, !isOlderThan(days, path: expanded) { return [] }
            return [expanded]
        case .removeContents:
            return fileHelper.contentsOfDirectory(atPath: expanded)
                .map { (expanded as NSString).appendingPathComponent($0) }
                .filter { child in
                    guard let days = target.olderThanDays else { return true }
                    return isOlderThan(days, path: child)
                }
        }
    }

    /// Tamanho estimado de um alvo (soma dos paths removíveis).
    func measuredSize(of target: CleanTarget) -> Int64 {
        let expanded = fileHelper.expandPath(target.path)
        guard fileHelper.fileExists(atPath: expanded) else { return 0 }
        return removablePaths(for: target, expanded: expanded)
            .reduce(0) { $0 + fileHelper.sizeOfDirectory(atPath: $1) }
    }

    func isOlderThan(_ days: Int, path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modDate) > Double(days) * 86400
    }

    private func displayName(for target: CleanTarget) -> String {
        target.label ?? (target.path as NSString).lastPathComponent
    }
}
