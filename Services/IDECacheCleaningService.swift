import Foundation

class IDECacheCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .ideCache

    // Caches de IDEs - JetBrains, VS Code, Cursor

    /// JetBrains - versões antigas podem ser removidas com segurança
    private func getJetBrainsPaths() -> [String] {
        var paths: [String] = []
        let jetBrainsPath = fileHelper.expandPath("~/Library/Application Support/JetBrains")

        if fileHelper.fileExists(atPath: jetBrainsPath) {
            let contents = fileHelper.contentsOfDirectory(atPath: jetBrainsPath)

            // Agrupar por produto para identificar versões antigas
            var productVersions: [String: [(version: String, path: String)]] = [:]

            for dir in contents {
                // Extrair nome do produto e versão (ex: Rider2024.3 -> Rider, 2024.3)
                if dir.range(of: #"^([A-Za-z]+)(\d+\.\d+)$"#, options: .regularExpression) != nil {
                    let fullPath = (jetBrainsPath as NSString).appendingPathComponent(dir)
                    let product = String(dir[dir.startIndex ..< dir.index(dir.startIndex, offsetBy: dir.count - 6)])
                    let version = String(dir.suffix(6))

                    if productVersions[product] == nil {
                        productVersions[product] = []
                    }
                    productVersions[product]?.append((version, fullPath))
                }
            }

            // Para cada produto, manter apenas a versão mais recente
            for (_, versions) in productVersions {
                let sorted = versions.sorted { $0.version > $1.version }
                if sorted.count > 1 {
                    // Adicionar todas exceto a mais recente
                    for i in 1 ..< sorted.count {
                        paths.append(sorted[i].path)
                    }
                }
            }
        }

        // Caches específicos do JetBrains (seguros de limpar)
        let jetBrainsCaches = [
            "~/Library/Caches/JetBrains",
            "~/Library/Logs/JetBrains"
        ]
        paths.append(contentsOf: jetBrainsCaches)

        return paths
    }

    /// VS Code - workspaceStorage pode crescer muito
    private let vscodePaths = [
        // WorkspaceStorage - pode acumular dados de projetos antigos (CUIDADO: 10GB+)
        "~/Library/Application Support/Code/User/workspaceStorage",
        // Cache de extensões antigas
        "~/Library/Application Support/Code/CachedExtensionVSIXs",
        // Cache de dados
        "~/Library/Application Support/Code/Cache",
        "~/Library/Application Support/Code/CachedData",
        // Logs
        "~/Library/Application Support/Code/logs",
        // Crashpad
        "~/Library/Application Support/Code/Crashpad",
        // GPU Cache
        "~/Library/Application Support/Code/GPUCache",
        // WebStorage
        "~/Library/Application Support/Code/WebStorage"
    ]

    /// Cursor - similar ao VS Code
    private let cursorPaths = [
        "~/Library/Application Support/Cursor/User/workspaceStorage",
        "~/Library/Application Support/Cursor/CachedExtensionVSIXs",
        "~/Library/Application Support/Cursor/Cache",
        "~/Library/Application Support/Cursor/CachedData",
        "~/Library/Application Support/Cursor/logs",
        "~/Library/Application Support/Cursor/Crashpad",
        "~/Library/Application Support/Cursor/GPUCache"
    ]

    /// Outros IDEs
    private let otherIDEPaths = [
        // Zed
        "~/Library/Application Support/Zed/logs",
        "~/Library/Caches/dev.zed.Zed",
        // Visual Studio for Mac
        "~/Library/Caches/VisualStudio",
        "~/Library/Logs/VisualStudio",
        // Sublime Text
        "~/Library/Caches/com.sublimetext.4",
        // Atom (se ainda existir)
        "~/Library/Application Support/Atom/Cache",
        "~/.atom/cache",
        // Warp terminal - pasta de autoupdate pode ficar grande
        "~/Library/Application Support/dev.warp.Warp-Stable/autoupdate",
        "~/Library/Caches/dev.warp.Warp-Stable",
        // Lapce editor
        "~/Library/Application Support/dev.lapce.Lapce-Stable/logs",
        "~/Library/Caches/dev.lapce.Lapce-Stable"
    ]

    // MARK: - Extensões obsoletas e histórico local

    /// Pastas de extensões dos editores baseados em VS Code. Cada uma tem um
    /// `.obsolete` (JSON `{ "<publisher.ext-versão>": true }`) onde o próprio
    /// editor anota versões substituídas que ainda não conseguiu apagar.
    private let extensionDirs = [
        "~/.vscode/extensions",
        "~/.vscode-insiders/extensions",
        "~/.cursor/extensions",
        "~/.trae/extensions",
        "~/.antigravity/extensions",
        "~/.windsurf/extensions",
        "~/.kiro/extensions"
    ]

    /// Histórico local por arquivo (Timeline → Local History). Cresce sem
    /// limite; só entradas sem toque há mais de 90 dias são removidas.
    private let localHistoryDirs = [
        "~/Library/Application Support/Code/User/History",
        "~/Library/Application Support/Cursor/User/History"
    ]

    static let localHistoryMaxAgeDays = 90

    /// Extensões marcadas em `.obsolete` que ainda existem em disco. Só o que o
    /// editor já decidiu descartar — nunca inferimos por versão.
    static func obsoleteExtensionPaths(extensionsDir: String) -> [String] {
        let helper = FileSystemHelper.shared
        let expanded = helper.expandPath(extensionsDir)
        let marker = (expanded as NSString).appendingPathComponent(".obsolete")
        guard let data = FileManager.default.contents(atPath: marker),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        return json.keys
            .filter { !$0.isEmpty && !$0.contains("/") && $0 != "." && $0 != ".." }
            .map { (expanded as NSString).appendingPathComponent($0) }
            .filter { helper.fileExists(atPath: $0) }
            .sorted()
    }

    /// Entradas de histórico local sem modificação há mais de `maxAgeDays`.
    static func staleLocalHistoryPaths(historyDir: String, maxAgeDays: Int = localHistoryMaxAgeDays) -> [String] {
        let helper = FileSystemHelper.shared
        let expanded = helper.expandPath(historyDir)
        guard helper.fileExists(atPath: expanded) else { return [] }
        let cutoff = Double(maxAgeDays) * 86400
        return helper.contentsOfDirectory(atPath: expanded)
            .map { (expanded as NSString).appendingPathComponent($0) }
            .filter { path in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let modDate = attrs[.modificationDate] as? Date else { return false }
                return Date().timeIntervalSince(modDate) > cutoff
            }
    }

    private func obsoleteExtensionPaths() -> [String] {
        extensionDirs.flatMap { Self.obsoleteExtensionPaths(extensionsDir: $0) }
    }

    private func staleLocalHistoryPaths() -> [String] {
        localHistoryDirs.flatMap { Self.staleLocalHistoryPaths(historyDir: $0) }
    }

    /// Mede extensões obsoletas e histórico local antigo para o relatório.
    private func scanObsoleteExtensionsAndHistory() -> (size: Int64, items: [String]) {
        var size: Int64 = 0
        var items: [String] = []

        let obsoleteExtensions = obsoleteExtensionPaths()
        if !obsoleteExtensions.isEmpty {
            let extensionsSize = obsoleteExtensions.reduce(Int64(0)) { $0 + fileHelper.sizeOfDirectory(atPath: $1) }
            size += extensionsSize
            items.append("Obsolete extensions: \(obsoleteExtensions.count) (\(fileHelper.formatBytes(extensionsSize)))")
        }

        let staleHistory = staleLocalHistoryPaths()
        let historySize = staleHistory.reduce(Int64(0)) { $0 + fileHelper.sizeOfDirectory(atPath: $1) }
        if historySize > 0 {
            size += historySize
            items.append(
                "Local history older than \(Self.localHistoryMaxAgeDays) days: \(fileHelper.formatBytes(historySize))"
            )
        }
        return (size, items)
    }

    private func cleanObsoleteExtensionsAndHistory(
        bytesRemoved: inout Int64, filesRemoved: inout Int, errors: inout [String]
    ) {
        for path in obsoleteExtensionPaths() + staleLocalHistoryPaths() {
            let size = fileHelper.sizeOfDirectory(atPath: path)
            if trashOrRemove(path) {
                bytesRemoved += size
                filesRemoved += 1
            } else {
                errors.append("Falha ao limpar: \((path as NSString).lastPathComponent)")
            }
        }
    }

    /// Lixeira primeiro (reversível); remoção direta só se a Lixeira recusar.
    private func trashOrRemove(_ path: String) -> Bool {
        if fileHelper.trashItem(atPath: path) { return true }
        do {
            try fileHelper.removeItem(atPath: path)
            return true
        } catch {
            logger.log("Falha ao remover: \(path)", level: .error)
            return false
        }
    }

    func scan(progress _: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []

        logger.log("Iniciando escaneamento de caches de IDEs", level: .info)

        // Extensões obsoletas (marcadas pelo próprio editor) e histórico local antigo
        let extras = scanObsoleteExtensionsAndHistory()
        totalSize += extras.size
        items.append(contentsOf: extras.items)

        // JetBrains - versões antigas
        let jetBrainsPaths = getJetBrainsPaths()
        var jetBrainsSize: Int64 = 0
        var jetBrainsOldVersions: [String] = []

        for path in jetBrainsPaths {
            let expandedPath = path.hasPrefix("~") ? fileHelper.expandPath(path) : path
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    jetBrainsSize += size
                    let name = (expandedPath as NSString).lastPathComponent
                    if !name.contains("Caches"), !name.contains("Logs") {
                        jetBrainsOldVersions.append(name)
                    }
                }
            }
        }

        if jetBrainsSize > 0 {
            totalSize += jetBrainsSize
            var description = "JetBrains: \(fileHelper.formatBytes(jetBrainsSize))"
            if !jetBrainsOldVersions.isEmpty {
                description += " (\(jetBrainsOldVersions.count) versões antigas)"
            }
            items.append(description)
            logger.log(
                "JetBrains: \(fileHelper.formatBytes(jetBrainsSize)) - \(jetBrainsOldVersions.joined(separator: ", "))",
                level: .debug
            )
        }

        // VS Code
        var vscodeSize: Int64 = 0
        for path in vscodePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                vscodeSize += fileHelper.sizeOfDirectory(atPath: expandedPath)
            }
        }
        if vscodeSize > 0 {
            totalSize += vscodeSize
            items.append("VS Code: \(fileHelper.formatBytes(vscodeSize))")
            logger.log("VS Code: \(fileHelper.formatBytes(vscodeSize))", level: .debug)
        }

        // Cursor
        var cursorSize: Int64 = 0
        for path in cursorPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                cursorSize += fileHelper.sizeOfDirectory(atPath: expandedPath)
            }
        }
        if cursorSize > 0 {
            totalSize += cursorSize
            items.append("Cursor: \(fileHelper.formatBytes(cursorSize))")
            logger.log("Cursor: \(fileHelper.formatBytes(cursorSize))", level: .debug)
        }

        // Outros IDEs
        var otherSize: Int64 = 0
        for path in otherIDEPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                otherSize += fileHelper.sizeOfDirectory(atPath: expandedPath)
            }
        }
        if otherSize > 0 {
            totalSize += otherSize
            items.append("Outros IDEs: \(fileHelper.formatBytes(otherSize))")
            logger.log("Outros IDEs: \(fileHelper.formatBytes(otherSize))", level: .debug)
        }

        logger.log("Escaneamento de IDEs concluído: \(fileHelper.formatBytes(totalSize))", level: .info)

        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: items.count,
            items: items
        )
    }

    func clean() async -> CleaningResult {
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []

        logger.log("Iniciando limpeza de caches de IDEs", level: .info)
        let startTime = Date()

        // Extensões obsoletas e histórico local antigo (Lixeira)
        cleanObsoleteExtensionsAndHistory(bytesRemoved: &bytesRemoved, filesRemoved: &filesRemoved, errors: &errors)

        // Limpar JetBrains (versões antigas e caches)
        let jetBrainsPaths = getJetBrainsPaths()
        for path in jetBrainsPaths {
            let expandedPath = path.hasPrefix("~") ? fileHelper.expandPath(path) : path
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                let name = (expandedPath as NSString).lastPathComponent

                do {
                    try fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                    logger.log("Removido JetBrains \(name): \(fileHelper.formatBytes(size))", level: .debug)
                } catch {
                    errors.append("Falha ao limpar: \(name)")
                    logger.log("Falha ao remover: \(expandedPath)", level: .error)
                }
            }
        }

        // Limpar VS Code (incluindo workspaceStorage)
        for path in vscodePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                do {
                    try fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                    logger.log("Removido VS Code cache: \(fileHelper.formatBytes(size))", level: .debug)
                } catch {
                    logger.log("Falha ao remover VS Code cache: \(path)", level: .error)
                }
            }
        }

        // Limpar Cursor (incluindo workspaceStorage)
        for path in cursorPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                do {
                    try fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                    logger.log("Removido Cursor cache: \(fileHelper.formatBytes(size))", level: .debug)
                } catch {
                    logger.log("Falha ao remover Cursor cache: \(path)", level: .error)
                }
            }
        }

        // Limpar outros IDEs
        for path in otherIDEPaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                do {
                    try fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                } catch {
                    // Ignorar erros
                }
            }
        }

        let executionTime = Date().timeIntervalSince(startTime)
        logger.log("Limpeza de IDEs concluída: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)

        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: executionTime,
            success: errors.isEmpty
        )
    }

    /// Limpar workspaceStorage antigos (projetos que não existem mais ou não foram acessados há muito tempo)
    private func cleanOldWorkspaceStorage(
        basePath: String,
        bytesRemoved: inout Int64,
        filesRemoved: inout Int,
        errors _: inout [String]
    ) async {
        let expandedPath = fileHelper.expandPath(basePath)
        guard fileHelper.fileExists(atPath: expandedPath) else { return }

        let contents = fileHelper.contentsOfDirectory(atPath: expandedPath)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())!

        for dir in contents {
            let workspacePath = (expandedPath as NSString).appendingPathComponent(dir)
            let workspaceJsonPath = (workspacePath as NSString).appendingPathComponent("workspace.json")

            // Verificar se foi acessado recentemente
            if let attrs = try? FileManager.default.attributesOfItem(atPath: workspacePath),
               let modDate = attrs[.modificationDate] as? Date
            {
                if modDate < cutoffDate {
                    // Verificar se o projeto original ainda existe
                    var projectStillExists = false

                    if fileHelper.fileExists(atPath: workspaceJsonPath),
                       let data = try? Data(contentsOf: URL(fileURLWithPath: workspaceJsonPath)),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let folder = json["folder"] as? String
                    {
                        // Converter URI para path e verificar
                        let projectPath = folder.replacingOccurrences(of: "file://", with: "")
                            .removingPercentEncoding ?? folder
                        projectStillExists = fileHelper.fileExists(atPath: projectPath)
                    }

                    // Se o projeto não existe mais ou é muito antigo, remover
                    if !projectStillExists {
                        let size = fileHelper.sizeOfDirectory(atPath: workspacePath)
                        do {
                            try fileHelper.removeItem(atPath: workspacePath)
                            bytesRemoved += size
                            filesRemoved += 1
                            logger.log(
                                "Removido workspace antigo: \(dir) (\(fileHelper.formatBytes(size)))",
                                level: .debug
                            )
                        } catch {
                            // Ignorar erros
                        }
                    }
                }
            }
        }
    }
}
