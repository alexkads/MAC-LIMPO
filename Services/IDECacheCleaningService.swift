import Foundation

class IDECacheCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .ideCache
    
    // Caches de IDEs - JetBrains, VS Code, Cursor
    
    // JetBrains - versões antigas podem ser removidas com segurança
    private func getJetBrainsPaths() -> [String] {
        var paths: [String] = []
        let jetBrainsPath = fileHelper.expandPath("~/Library/Application Support/JetBrains")
        
        if fileHelper.fileExists(atPath: jetBrainsPath) {
            let contents = fileHelper.contentsOfDirectory(atPath: jetBrainsPath)
            
            // Agrupar por produto para identificar versões antigas
            var productVersions: [String: [(version: String, path: String)]] = [:]
            
            for dir in contents {
                // Extrair nome do produto e versão (ex: Rider2024.3 -> Rider, 2024.3)
                if let match = dir.range(of: #"^([A-Za-z]+)(\d+\.\d+)$"#, options: .regularExpression) {
                    let fullPath = (jetBrainsPath as NSString).appendingPathComponent(dir)
                    let product = String(dir[dir.startIndex..<dir.index(dir.startIndex, offsetBy: dir.count - 6)])
                    let version = String(dir.suffix(6))
                    
                    if productVersions[product] == nil {
                        productVersions[product] = []
                    }
                    productVersions[product]?.append((version, fullPath))
                }
            }
            
            // Para cada produto, manter apenas a versão mais recente
            for (product, versions) in productVersions {
                let sorted = versions.sorted { $0.version > $1.version }
                if sorted.count > 1 {
                    // Adicionar todas exceto a mais recente
                    for i in 1..<sorted.count {
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
    
    // VS Code - workspaceStorage pode crescer muito
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
    
    // Cursor - similar ao VS Code
    private let cursorPaths = [
        "~/Library/Application Support/Cursor/User/workspaceStorage",
        "~/Library/Application Support/Cursor/CachedExtensionVSIXs",
        "~/Library/Application Support/Cursor/Cache",
        "~/Library/Application Support/Cursor/CachedData",
        "~/Library/Application Support/Cursor/logs",
        "~/Library/Application Support/Cursor/Crashpad",
        "~/Library/Application Support/Cursor/GPUCache"
    ]
    
    // Outros IDEs
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
        "~/.atom/cache"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        logger.log("Iniciando escaneamento de caches de IDEs", level: .info)
        
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
                    if !name.contains("Caches") && !name.contains("Logs") {
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
            logger.log("JetBrains: \(fileHelper.formatBytes(jetBrainsSize)) - \(jetBrainsOldVersions.joined(separator: ", "))", level: .debug)
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
        
        // Limpar JetBrains (versões antigas e caches)
        let jetBrainsPaths = self.getJetBrainsPaths()
        for path in jetBrainsPaths {
            let expandedPath = path.hasPrefix("~") ? self.fileHelper.expandPath(path) : path
            if self.fileHelper.fileExists(atPath: expandedPath) {
                let size = self.fileHelper.sizeOfDirectory(atPath: expandedPath)
                let name = (expandedPath as NSString).lastPathComponent
                
                // Para versões antigas, remover completamente
                // Para caches/logs, limpar conteúdo
                do {
                    try self.fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                    logger.log("Removido JetBrains \(name): \(self.fileHelper.formatBytes(size))", level: .debug)
                } catch {
                    errors.append("Falha ao limpar: \(name)")
                    logger.log("Falha ao remover: \(expandedPath)", level: .error)
                }
            }
        }
        
        // Limpar VS Code (apenas caches, não workspaceStorage inteiro por segurança)
        // WorkspaceStorage contém dados importantes - limpar apenas os muito antigos
        await self.cleanOldWorkspaceStorage(basePath: "~/Library/Application Support/Code/User/workspaceStorage", bytesRemoved: &bytesRemoved, filesRemoved: &filesRemoved, errors: &errors)
        
        // Limpar outros caches do VS Code
        for path in self.vscodePaths.filter({ !$0.contains("workspaceStorage") }) {
            let expandedPath = self.fileHelper.expandPath(path)
            if self.fileHelper.fileExists(atPath: expandedPath) {
                let size = self.fileHelper.sizeOfDirectory(atPath: expandedPath)
                do {
                    try self.fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                    logger.log("Removido VS Code cache: \(self.fileHelper.formatBytes(size))", level: .debug)
                } catch {
                    // Ignorar erros em caches
                }
            }
        }
        
        // Limpar Cursor
        await self.cleanOldWorkspaceStorage(basePath: "~/Library/Application Support/Cursor/User/workspaceStorage", bytesRemoved: &bytesRemoved, filesRemoved: &filesRemoved, errors: &errors)
        
        for path in self.cursorPaths.filter({ !$0.contains("workspaceStorage") }) {
            let expandedPath = self.fileHelper.expandPath(path)
            if self.fileHelper.fileExists(atPath: expandedPath) {
                let size = self.fileHelper.sizeOfDirectory(atPath: expandedPath)
                do {
                    try self.fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                } catch {
                    // Ignorar erros
                }
            }
        }
        
        // Limpar outros IDEs
        for path in self.otherIDEPaths {
            let expandedPath = self.fileHelper.expandPath(path)
            if self.fileHelper.fileExists(atPath: expandedPath) {
                let size = self.fileHelper.sizeOfDirectory(atPath: expandedPath)
                do {
                    try self.fileHelper.removeItem(atPath: expandedPath)
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
    
    // Limpar workspaceStorage antigos (projetos que não existem mais ou não foram acessados há muito tempo)
    private func cleanOldWorkspaceStorage(basePath: String, bytesRemoved: inout Int64, filesRemoved: inout Int, errors: inout [String]) async {
        let expandedPath = fileHelper.expandPath(basePath)
        guard fileHelper.fileExists(atPath: expandedPath) else { return }
        
        let contents = fileHelper.contentsOfDirectory(atPath: expandedPath)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        
        for dir in contents {
            let workspacePath = (expandedPath as NSString).appendingPathComponent(dir)
            let workspaceJsonPath = (workspacePath as NSString).appendingPathComponent("workspace.json")
            
            // Verificar se foi acessado recentemente
            if let attrs = try? FileManager.default.attributesOfItem(atPath: workspacePath),
               let modDate = attrs[.modificationDate] as? Date {
                
                if modDate < cutoffDate {
                    // Verificar se o projeto original ainda existe
                    var projectStillExists = false
                    
                    if fileHelper.fileExists(atPath: workspaceJsonPath),
                       let data = try? Data(contentsOf: URL(fileURLWithPath: workspaceJsonPath)),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let folder = json["folder"] as? String {
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
                            logger.log("Removido workspace antigo: \(dir) (\(fileHelper.formatBytes(size)))", level: .debug)
                        } catch {
                            // Ignorar erros
                        }
                    }
                }
            }
        }
    }
}
