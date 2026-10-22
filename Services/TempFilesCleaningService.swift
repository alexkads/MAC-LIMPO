import Foundation

class TempFilesCleaningService: BaseCleaningService, CleaningService, @unchecked Sendable {
    let category: CleaningCategory = .tempFiles

    /// O /tmp não entra aqui: tem regra própria (`staleTemporaryItems`). Nesta
    /// lista ele era esvaziado inteiro, anulando o filtro de idade.
    private let tempPaths = [
        "~/Library/Caches/com.apple.bird", // iCloud
        "~/Library/Caches/CloudKit",
        "~/Library/Caches/com.apple.Safari/Webpage Previews"
    ]

    /// NÃO limpar estes diretórios (críticos para o sistema)
    private let excludedPaths = [
        "com.apple.dock",
        "com.apple.finder",
        "com.apple.Safari", // Exceto o subdiretório específico acima
        "com.apple.loginwindow",
        "com.apple.bird", // Exceto o específico acima
        "com.apple.Music",
        "com.apple.Photos"
    ]

    func scan(progress _: (@Sendable (String) -> Void)?) async -> ScanResult {
        Logger.shared.scan(category: "TempFiles", message: "Starting scan")

        var totalSize: Int64 = 0
        var items: [String] = []

        for path in tempPaths {
            let expandedPath = fileHelper.expandPath(path)

            Logger.shared.debug("Scanning path: \(expandedPath)")

            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    totalSize += size
                    let pathName = (path as NSString).lastPathComponent
                    let formatted = fileHelper.formatBytes(size)
                    items.append("\(pathName): \(formatted)")
                    Logger.shared.debug("Found: \(pathName) - \(formatted)")
                }
            } else {
                Logger.shared.debug("Path does not exist: \(expandedPath)")
            }
        }

        // /tmp: só o que a limpeza de fato leva
        let staleTmp = Self.staleTemporaryItems()
        let tmpSize = await fileHelper.sizesOfDirectoriesAsync(atPaths: staleTmp).values.reduce(0, +)
        if tmpSize > 0 {
            totalSize += tmpSize
            items.append("tmp: \(fileHelper.formatBytes(tmpSize))")
        }

        Logger.shared.scan(
            category: "TempFiles",
            message: "Scan complete: \(fileHelper.formatBytes(totalSize)) in \(items.count) locations"
        )

        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: items.count,
            items: items
        )
    }

    func clean() async -> CleaningResult {
        Logger.shared.clean(category: "TempFiles", message: "Starting cleanup")

        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []

        // Limpa /tmp com cuidado
        Logger.shared.debug("Cleaning /tmp directory")
        await cleanTmpDirectory(bytesRemoved: &bytesRemoved, filesRemoved: &filesRemoved, errors: &errors)

        // Limpa outros caches seguros
        for path in tempPaths {
            let expandedPath = fileHelper.expandPath(path)

            Logger.shared.debug("Cleaning: \(expandedPath)")

            if fileHelper.fileExists(atPath: expandedPath) {
                await cleanDirectory(
                    atPath: expandedPath,
                    bytesRemoved: &bytesRemoved,
                    filesRemoved: &filesRemoved,
                    errors: &errors
                )
            } else {
                Logger.shared.debug("Path does not exist, skipping: \(expandedPath)")
            }
        }

        let executionTime = Date().timeIntervalSince(startTime)

        // Considera sucesso se conseguiu limpar algo OU se não havia nada para limpar
        let success = filesRemoved > 0 || (errors.isEmpty && filesRemoved == 0)

        if success {
            Logger.shared
                .success(
                    "TempFiles cleanup complete: \(fileHelper.formatBytes(bytesRemoved)), \(filesRemoved) files, \(errors.count) errors"
                )
        } else {
            Logger.shared.error("TempFiles cleanup failed with \(errors.count) errors")
            for error in errors {
                Logger.shared.error("  - \(error)")
            }
        }

        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: executionTime,
            success: success
        )
    }

    static let tmpMaxAgeDays = 7

    /// Itens de `folder` (o /tmp) que podem ir para a Lixeira: do usuário,
    /// arquivos ou pastas comuns, sem nada modificado dentro há mais de 7 dias e
    /// sem socket ou FIFO — é por eles que processos vivos conversam (ssh-agent,
    /// tmux, IDEs), e tirá-los derruba essas sessões. Ocultos e `com.apple.*`
    /// ficam.
    static func staleTemporaryItems(
        in folder: String = "/tmp",
        olderThanDays days: Int = tmpMaxAgeDays,
        now: Date = Date(),
        owner: uid_t = getuid()
    ) -> [String] {
        let helper = FileSystemHelper.shared
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        return helper.contentsOfDirectory(atPath: folder)
            .filter { !$0.hasPrefix(".") && !$0.hasPrefix("com.apple.") }
            .map { (folder as NSString).appendingPathComponent($0) }
            .filter { path in
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == owner,
                      let type = attributes[.type] as? FileAttributeType,
                      type == .typeRegular || type == .typeDirectory
                else { return false }
                return !helper.hasModifications(since: cutoff, atPath: path)
                    && !(type == .typeDirectory && containsSocketOrPipe(atPath: path))
            }
            .sorted()
    }

    /// Há socket ou FIFO dentro da pasta `path`? Na dúvida (pasta ilegível), sim.
    static func containsSocketOrPipe(atPath path: String) -> Bool {
        var unreadable = false
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileResourceTypeKey],
            errorHandler: { _, _ in
                unreadable = true
                return false
            }
        ) else { return true }
        while let child = enumerator.nextObject() as? URL {
            let type = try? child.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType
            if type == .socket || type == .namedPipe { return true }
        }
        return unreadable
    }

    /// /tmp vai para a Lixeira, não é apagado de vez: o que alguém guardou ali
    /// ainda pode voltar.
    private func cleanTmpDirectory(bytesRemoved: inout Int64, filesRemoved: inout Int, errors: inout [String]) async {
        let stale = Self.staleTemporaryItems()
        for itemPath in stale {
            let size = fileHelper.sizeOfDirectory(atPath: itemPath)
            if fileHelper.trashItem(atPath: itemPath) {
                bytesRemoved += size
                filesRemoved += 1
            } else {
                errors.append(String(localized: "Could not move \((itemPath as NSString).lastPathComponent) to the Trash."))
            }
        }
        Logger.shared.info("/tmp cleanup: \(stale.count) stale items")
    }

    private func cleanDirectory(
        atPath path: String,
        bytesRemoved: inout Int64,
        filesRemoved: inout Int,
        errors: inout [String]
    ) async {
        let contents = fileHelper.contentsOfDirectory(atPath: path)

        Logger.shared.debug("Cleaning directory: \(path) (\(contents.count) items)")

        var removed = 0
        var skipped = 0

        for item in contents {
            // Pula arquivos ocultos e do sistema
            if item.hasPrefix(".") {
                skipped += 1
                continue
            }

            let itemPath = (path as NSString).appendingPathComponent(item)

            // Verifica se está na lista de exclusão
            var shouldSkip = false
            for excluded in excludedPaths {
                if itemPath.contains(excluded) {
                    shouldSkip = true
                    Logger.shared.debug("Skipping excluded path: \(itemPath)")
                    break
                }
            }

            if shouldSkip {
                skipped += 1
                continue
            }

            do {
                // Calcula tamanho ANTES de remover
                let size = fileHelper.sizeOfDirectory(atPath: itemPath)

                // Remove o item
                try fileHelper.removeItem(atPath: itemPath)

                // Só conta se conseguiu remover
                bytesRemoved += size
                filesRemoved += 1
                removed += 1

                Logger.shared.debug("Removed: \(item) (\(fileHelper.formatBytes(size)))")
            } catch let error as NSError {
                let itemName = (itemPath as NSString).lastPathComponent

                // Diferencia entre erros de permissão (esperados) e erros reais
                if error.domain == NSCocoaErrorDomain, error.code == 513 || error.code == 257 {
                    // 513 = NSFileWriteNoPermissionError
                    // 257 = NSFileReadNoPermissionError
                    Logger.shared.debug("Permission denied (expected): \(itemName)")
                    skipped += 1
                } else if error.domain == NSPOSIXErrorDomain, error.code == 1 || error.code == 13 {
                    // 1 = EPERM (Operation not permitted)
                    // 13 = EACCES (Permission denied)
                    Logger.shared.debug("Permission denied (expected): \(itemName)")
                    skipped += 1
                } else {
                    // Erro real - reporta ao usuário
                    let errorMsg = String(localized: "Failed to remove \(itemName): \(error.localizedDescription)")
                    errors.append(errorMsg)
                    Logger.shared.warning(errorMsg)
                    skipped += 1
                }
            }
        }

        Logger.shared.info("Directory \(path): removed \(removed), skipped \(skipped)")
    }
}
