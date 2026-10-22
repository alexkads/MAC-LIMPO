import Foundation

/// Downloads esquecidos em ~/Downloads. São arquivos do usuário: vão para a
/// Lixeira (nunca apagados de vez) e só entram os que provam estar parados —
/// baixados há mais de 30 dias e sem nenhuma modificação nesse período, nem
/// dentro das pastas. Antes valia só a data do item de cima, e uma pasta antiga
/// com arquivos editados ontem sumia inteira.
class DownloadsCleaningService: BaseCleaningService, CleaningService, @unchecked Sendable {
    let category: CleaningCategory = .downloads

    static let maxAgeDays = 30
    private let downloadsPath = "~/Downloads"

    /// Itens de `folder` que podem ir para a Lixeira em `now`. Ocultos
    /// (.DS_Store, .localized) ficam.
    static func staleItems(in folder: String, olderThanDays days: Int = maxAgeDays, now: Date = Date()) -> [String] {
        let helper = FileSystemHelper.shared
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        return helper.contentsOfDirectory(atPath: folder)
            .filter { !$0.hasPrefix(".") }
            .map { (folder as NSString).appendingPathComponent($0) }
            .filter { path in
                guard let added = helper.dateAdded(atPath: path), added < cutoff else { return false }
                return !helper.hasModifications(since: cutoff, atPath: path)
            }
            .sorted()
    }

    func scan(progress _: (@Sendable (String) -> Void)?) async -> ScanResult {
        let items = Self.staleItems(in: fileHelper.expandPath(downloadsPath))
        let sizes = await fileHelper.sizesOfDirectoriesAsync(atPaths: items)

        return ScanResult(
            category: category,
            estimatedSize: sizes.values.reduce(0, +),
            itemCount: items.count,
            items: items.prefix(10).map { ($0 as NSString).lastPathComponent }
        )
    }

    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []

        for itemPath in Self.staleItems(in: fileHelper.expandPath(downloadsPath)) {
            let size = fileHelper.sizeOfDirectory(atPath: itemPath)
            if fileHelper.trashItem(atPath: itemPath) {
                bytesRemoved += size
                filesRemoved += 1
            } else {
                errors.append(String(localized: "Could not move \((itemPath as NSString).lastPathComponent) to the Trash."))
            }
        }

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
