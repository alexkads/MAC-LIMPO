import Foundation

/// Esvazia a Lixeira — a única categoria que apaga de vez o que o usuário já
/// mandou para lá. Por isso fica fora do Clean All (`includedInCleanAll`).
class TrashCleaningService: BaseCleaningService, CleaningService, @unchecked Sendable {
    let category: CleaningCategory = .trash

    private let trashPath = "~/.Trash"

    func scan(progress _: (@Sendable (String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var itemCount = 0

        let expandedPath = fileHelper.expandPath(trashPath)
        if fileHelper.fileExists(atPath: expandedPath) {
            totalSize = fileHelper.sizeOfDirectory(atPath: expandedPath)
            itemCount = fileHelper.contentsOfDirectory(atPath: expandedPath).count
        }

        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: itemCount,
            items: ["\(itemCount) items in Trash"]
        )
    }

    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []

        // Item por item, fora da MainActor (apagar GBs travava a interface), e um
        // item preso não impede os demais. Sem Acesso Total ao Disco a listagem
        // falha — isso vira erro visível, não uma Lixeira "vazia".
        let expandedPath = fileHelper.expandPath(trashPath)
        let contents: [String]
        do {
            contents = fileHelper.fileExists(atPath: expandedPath)
                ? try FileManager.default.contentsOfDirectory(atPath: expandedPath)
                : []
        } catch {
            contents = []
            errors.append(String(localized: "Failed to empty trash: \(error.localizedDescription)"))
        }
        for item in contents {
            let itemPath = (expandedPath as NSString).appendingPathComponent(item)
            let size = fileHelper.sizeOfDirectory(atPath: itemPath)
            do {
                try fileHelper.removeItem(atPath: itemPath)
                bytesRemoved += size
                filesRemoved += 1
            } catch {
                errors.append(String(localized: "Failed to remove \(item): \(error.localizedDescription)"))
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
