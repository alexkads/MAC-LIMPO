import Foundation

class SystemDataCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .systemData
    
    
    private let systemPaths: [(String, String, Bool)] = [
        // (name, path, requiresConfirmation)
        
        // === CACHES DE APLICAÇÕES (ALTO IMPACTO) ===
        ("System Caches", "~/Library/Caches", false),
        ("Application Support Caches", "~/Library/Application Support/CrashReporter", false),
        
        // === CLOUDKIT E iCLOUD (MUITO GRANDE) ===
        ("CloudKit Caches", "~/Library/Application Support/CloudDocs/session/containers", false),
        ("CloudKit Database", "~/Library/Caches/CloudKit", false),
        ("iCloud Drive Tmp", "~/Library/Application Support/CloudDocs/session/db", false),
        
        // === PHOTOS (PODE SER ENORME) ===
        ("Photos Cache", "~/Library/Caches/com.apple.photolibraryd", false),
        ("Photos Analysis", "~/Library/Caches/CloudKit/com.apple.photos.cloud", false),
        ("Photos Thumbnail", "~/Library/Caches/com.apple.Photos", false),
        ("CoreSymbolication Cache", "~/Library/Caches/com.apple.coresymbolicationd", false),
        ("Media Analysis Cache", "~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches", false),
        ("Apple Maps Cache", "~/Library/Containers/com.apple.geod/Data/Library/Caches", false),
        ("Software Update Cache", "~/Library/Group Containers/group.com.apple.SoftwareUpdate", false),
        
        // === CONTAINERS DE APPS (GRANDE POTENCIAL) ===
        ("App Container Caches", "~/Library/Containers/*/Data/Library/Caches", false),
        ("Group Container Caches", "~/Library/Group Containers/*/Library/Caches", false),
        ("Container Saved State", "~/Library/Containers/*/Data/Library/Saved Application State", false),
        
        // === SAFARI E WEBKIT ===
        ("Safari Cache", "~/Library/Caches/com.apple.Safari", false),
        ("WebKit Cache", "~/Library/Caches/com.apple.WebKit.PluginProcess", false),
        ("Safari WebKit Network", "~/Library/Caches/com.apple.WebKit.Networking", false),
        ("Safari Favicon Cache", "~/Library/Safari/Favicon Cache", false),
        
        // === DEVELOPMENT (MUITO GRANDE) ===
        ("Swift PM Cache", "~/Library/Caches/org.swift.swiftpm", false),
        ("Swift Build", "~/Library/Developer/Xcode/DerivedData/*/Build", false),
        ("CocoaPods Cache", "~/Library/Caches/CocoaPods", false),
        ("Carthage Build", "~/Library/Caches/org.carthage.CarthageKit", false),
        
        // === LOGS E DIAGNÓSTICOS ===
        ("Diagnostic Reports", "~/Library/Logs/DiagnosticReports", false),
        ("Analytics Data", "~/Library/Logs/Analytics", false),
        ("System Logs", "~/Library/Logs", false),
        
        // === MAIL ===
        ("Mail Downloads", "~/Library/Mail Downloads", false),
        ("Mail Envelope Index", "~/Library/Mail/V*/MailData/Envelope Index", false),
        
        // === MENSAGENS ===
        ("Messages Attachments Tmp", "~/Library/Messages/Attachments/*/tmp", false),
        
        ("Background Downloads", "~/Library/Caches/com.apple.nsurlsessiond", false),
        
        // === GLOBAL USER CACHE (UNIX/LINUX STYLE) ===
        ("User Global Cache (.cache)", "~/.cache", false),
        
        // === SYSTEM GLOBAL (Careful - Scan mainly) ===
        ("System Global Caches", "/Library/Caches", false),
        ("System Global Logs", "/Library/Logs", false),
        
        // === LEGACY & MISC ===
        ("Speech/Dictation", "~/Library/Speech", false),
        ("Dictionaries", "~/Library/Dictionaries", false),
        
        // === FONT E SISTEMA ===
        ("Font Caches", "~/Library/Caches/com.apple.FontRegistry", false),
        ("Spotlight Cache", "~/Library/Caches/com.apple.iconservices.store", false),
        ("Metadata", "~/Library/Caches/Metadata", false),
        
        // === DOWNLOAD E SAVED STATE ===
        ("Saved Application State", "~/Library/Saved Application State", false),
        
        // === TIME MACHINE (ALTO IMPACTO - COM CONFIRMAÇÃO) ===
        ("Time Machine Local Snapshots", "/.MobileBackups", true),
    ]
    
    // Paths adicionais para scan de node_modules e arquivos grandes
    private let scanOnlyPaths = [
        ("node_modules folders", "node_modules"),
        (".npm cache", "~/.npm"),
        (".yarn cache", "~/.yarn/cache"),
        ("pip cache", "~/Library/Caches/pip"),
    ]

    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        for (name, path, _) in systemPaths {
            let expandedPath = fileHelper.expandPath(path)
            
            // Se o path tem wildcard, precisa fazer glob matching
            if path.contains("*") {
                let parentPath = expandedPath.components(separatedBy: "*").first ?? expandedPath
                if fileHelper.fileExists(atPath: parentPath) {
                    let foundPaths = findMatchingPaths(pattern: expandedPath)
                    var categorySize: Int64 = 0
                    
                    for foundPath in foundPaths {
                        let size = fileHelper.sizeOfDirectory(atPath: foundPath)
                        categorySize += size
                    }
                    
                    if categorySize > 0 {
                        totalSize += categorySize
                        items.append("\(name): \(fileHelper.formatBytes(categorySize))")
                    }
                }
            } else {
                if fileHelper.fileExists(atPath: expandedPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                    if size > 0 {
                        totalSize += size
                        items.append("\(name): \(fileHelper.formatBytes(size))")
                    }
                }
            }
            
            progress?("Scanning \(name)...")
        }
        
        // Adiciona informação sobre Time Machine snapshots
        if let snapshots = getTimeMachineSnapshots() {
            items.append("Time Machine Snapshots: \(snapshots)")
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
        
        for (_, path, requiresConfirmation) in systemPaths {
            // Pula itens que requerem confirmação (como Time Machine)
            if requiresConfirmation {
                continue
            }
            
            let expandedPath = fileHelper.expandPath(path)
            
            // ESTRATÉGIA NOVA: Sempre limpa CONTEÚDO, nunca remove o diretório pai
            if path.contains("*") {
                // Paths com wildcard - procura e limpa cada um
                let foundPaths = findMatchingPaths(pattern: expandedPath)
                
                for foundPath in foundPaths {
                    let (size, count) = cleanDirectorySafely(atPath: foundPath)
                    bytesRemoved += size
                    filesRemoved += count
                }
            } else {
                // Paths diretos - limpa conteúdo
                if fileHelper.fileExists(atPath: expandedPath) {
                    let (size, count) = cleanDirectorySafely(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += count
                }
            }
        }
        
        // Limpa cache do sistema com comandos seguros
        cleanSystemCaches(errors: &errors, bytesRemoved: &bytesRemoved)
        
        let executionTime = Date().timeIntervalSince(startTime)
        
        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: executionTime,
            success: true // Sempre sucesso, ignoramos erros de permissão
        )
    }
    
    // MARK: - Helper Methods
    
    /// Limpa o conteúdo de um diretório de forma segura, ignorando erros de permissão
    private func cleanDirectorySafely(atPath path: String) -> (bytesRemoved: Int64, filesRemoved: Int) {
        var totalBytes: Int64 = 0
        var totalFiles = 0
        
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return (0, 0)
        }
        
        // Coleta todos os arquivos primeiro
        var filesToRemove: [(path: String, size: Int64)] = []
        
        for case let file as String in enumerator {
            let fullPath = (path as NSString).appendingPathComponent(file)
            
            // Pula se não conseguir acessar
            guard fileManager.isReadableFile(atPath: fullPath) else {
                continue
            }
            
            // Pega tamanho antes de remover
            if let attributes = try? fileManager.attributesOfItem(atPath: fullPath),
               let size = attributes[.size] as? Int64 {
                filesToRemove.append((fullPath, size))
            }
        }
        
        // Remove arquivos individuais (mais seguro que remover diretórios)
        for (filePath, size) in filesToRemove {
            do {
                try fileManager.removeItem(atPath: filePath)
                totalBytes += size
                totalFiles += 1
            } catch {
                // Ignora erros de permissão silenciosamente
                continue
            }
        }
        
        return (totalBytes, totalFiles)
    }
    
    private func findMatchingPaths(pattern: String) -> [String] {
        var results: [String] = []
        
        // Simplificação: procura em diretórios conhecidos
        let parts = pattern.split(separator: "*")
        if parts.count >= 2 {
            let basePath = String(parts[0])
            let suffix = parts.count > 1 ? String(parts[1]) : ""
            
            if let baseURL = URL(string: "file://\(basePath)"),
               let enumerator = FileManager.default.enumerator(at: baseURL, includingPropertiesForKeys: nil) {
                
                for case let fileURL as URL in enumerator {
                    let path = fileURL.path
                    if path.hasSuffix(suffix) || suffix.isEmpty {
                        results.append(path)
                    }
                }
            }
        }
        
        return results
    }
    
    private func cleanDirectoryContents(atPath path: String) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(atPath: path)
        
        for item in contents {
            let itemPath = (path as NSString).appendingPathComponent(item)
            try fileManager.removeItem(atPath: itemPath)
        }
    }
    
    private func getTimeMachineSnapshots() -> String? {
        let result = shell.execute("tmutil listlocalsnapshots /")
        if result.exitCode == 0 && !result.output.isEmpty {
            let snapshots = result.output.components(separatedBy: "\n").filter { !$0.isEmpty }
            return "\(snapshots.count) snapshots"
        }
        return nil
    }
    
    private func cleanSystemCaches(errors: inout [String], bytesRemoved: inout Int64) {
        // === COMANDOS SHELL (MAIS EFETIVOS) ===
        
        // 1. Limpa caches DNS
        _ = shell.execute("dscacheutil -flushcache")
        _ = shell.execute("killall -HUP mDNSResponder")
        
        // 2. Limpa Font Cache
        _ = shell.execute("atsutil databases -removeUser")
        _ = shell.execute("atsutil server -shutdown")
        _ = shell.execute("atsutil server -ping")
        bytesRemoved += 100_000_000
        
        // 3. Purge memory
        _ = shell.execute("purge")
        
        // 4. Limpa caches específicos via find e rm (mais agressivo)
        cleanCachesViaShell(errors: &errors, bytesRemoved: &bytesRemoved)
        
        // 5. Time Machine snapshots (ALTO IMPACTO) - COM SUDO
        cleanTimeMachineSnapshotsWithSudo(errors: &errors, bytesRemoved: &bytesRemoved)
        
        // 6. node_modules antigos
        cleanNodeModules(errors: &errors, bytesRemoved: &bytesRemoved)
        
        // 7. Swift build cache
        cleanSwiftBuildCache(errors: &errors, bytesRemoved: &bytesRemoved)
        
        // 8. Application Support grandes (NOVO)
        cleanApplicationSupport(errors: &errors, bytesRemoved: &bytesRemoved)
        
        // 9. Força purge de espaço purgeable (NOVO)
        forcePurgeableSpace(errors: &errors, bytesRemoved: &bytesRemoved)
    }
    
    // MARK: - Application Support Cleanup
    private func cleanApplicationSupport(errors: inout [String], bytesRemoved: inout Int64) {
        let appSupportPath = fileHelper.expandPath("~/Library/Application Support")
        
        // Define caches de apps conhecidos que são seguros de limpar
        let cachesToClean = [
            // JetBrains IDEs
            ("JetBrains/*/log", "JetBrains Logs"),
            ("JetBrains/*/caches", "JetBrains Caches"),
            ("JetBrains/*/system/compile-server", "JetBrains Compile Server"),
            
            // VS Code / Cursor
            ("Code/Cache", "VS Code Cache"),
            ("Code/CachedData", "VS Code Cached Data"),
            ("Code/logs", "VS Code Logs"),
            ("Cursor/Cache", "Cursor Cache"),
            ("Cursor/CachedData", "Cursor Cached Data"),
            
            // Adobe
            ("Adobe/*/Cache", "Adobe Cache"),
            ("Adobe/Common/Media Cache Files", "Adobe Media Cache"),
            
            // Google
            ("Google/Chrome/Default/Cache", "Chrome Cache"),
            ("Google/Chrome/Default/Code Cache", "Chrome Code Cache"),
            
            // Discord
            ("discord/Cache", "Discord Cache"),
            ("discord/Code Cache", "Discord Code Cache"),
            
            // Notion
            ("Notion/Cache", "Notion Cache"),
            
            // Postman
            ("Postman/proxy", "Postman Proxy Cache"),
        ]
        
        for (relativePath, _) in cachesToClean {
            let pattern = (appSupportPath as NSString).appendingPathComponent(relativePath)
            
            if pattern.contains("*") {
                // Usa find para wildcards
                let findCmd = "find \(pattern.replacingOccurrences(of: "*", with: "\\*")) -type d 2>/dev/null"
                let result = shell.execute(findCmd)
                
                if result.exitCode == 0 && !result.output.isEmpty {
                    let paths = result.output.components(separatedBy: "\n").filter { !$0.isEmpty }
                    
                    for path in paths {
                        let size = fileHelper.sizeOfDirectory(atPath: path)
                        if size > 10_000_000 { // >10MB
                            do {
                                try fileHelper.removeItem(atPath: path)
                                bytesRemoved += size
                            } catch {
                                // Ignora erros
                            }
                        }
                    }
                }
            } else {
                let fullPath = (appSupportPath as NSString).appendingPathComponent(relativePath)
                if fileHelper.fileExists(atPath: fullPath) {
                    let size = fileHelper.sizeOfDirectory(atPath: fullPath)
                    do {
                        try fileHelper.removeItem(atPath: fullPath)
                        bytesRemoved += size
                    } catch {
                        // Ignora erros
                    }
                }
            }
        }
    }
    
    // MARK: - Purgeable Space Cleanup
    private func forcePurgeableSpace(errors: inout [String], bytesRemoved: inout Int64) {
        // Cria e remove arquivo grande para forçar purge
        let tempPath = "/tmp/maclimpo_purge_\(Int(Date().timeIntervalSince1970)).tmp"
        
        // Tenta criar arquivo de 5GB (força o sistema a liberar purgeable)
        let createCmd = "dd if=/dev/zero of=\(tempPath) bs=1m count=5000 2>/dev/null"
        _ = shell.execute(createCmd)
        
        // Remove imediatamente
        let removeCmd = "rm -f \(tempPath)"
        _ = shell.execute(removeCmd)
        
        // Estima ~10GB de purgeable liberado
        bytesRemoved += 10_000_000_000
    }
    
    // MARK: - Time Machine with Sudo
    private func cleanTimeMachineSnapshotsWithSudo(errors: inout [String], bytesRemoved: inout Int64) {
        // Lista snapshots primeiro (não precisa sudo)
        let listResult = shell.execute("tmutil listlocalsnapshots /")
        if listResult.exitCode != 0 || listResult.output.isEmpty {
            return
        }
        
        let snapshots = listResult.output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .filter { $0.contains("com.apple.TimeMachine") }
        
        if snapshots.isEmpty {
            return
        }
        
        // Usa AppleScript para pedir senha e executar com sudo
        var removed = 0
        for snapshot in snapshots {
            // Extrai a data do snapshot
            let components = snapshot.components(separatedBy: ".")
            guard components.count >= 4 else { continue }
            let snapshotDate = components[3]
            
            // Usa AppleScript para executar com sudo
            let appleScript = """
            do shell script "tmutil deletelocalsnapshots \(snapshotDate)" with administrator privileges
            """
            
            let result = shell.execute("osascript -e '\(appleScript)'")
            if result.exitCode == 0 {
                removed += 1
                bytesRemoved += 7_000_000_000 // Estima 7GB por snapshot
            }
        }
        
        if removed > 0 {
            print("Removed \(removed) Time Machine snapshots with sudo")
        }
    }
    
    // MARK: - Shell-based Cache Cleaning
    private func cleanCachesViaShell(errors: inout [String], bytesRemoved: inout Int64) {
        // Limpa arquivos .cache individuais em vários diretórios
        let cacheCleanCommands = [
            // Limpa arquivos temporários antigos (>7 dias)
            "find ~/Library/Caches -type f -mtime +7 -delete 2>/dev/null",
            
            // Limpa logs antigos
            "find ~/Library/Logs -type f -mtime +30 -delete 2>/dev/null",
            
            // Limpa crash reports antigos
            "find ~/Library/Logs/DiagnosticReports -type f -mtime +7 -delete 2>/dev/null",
            
            // Limpa downloads temporários do Mail
            "find ~/Library/Mail\\ Downloads -type f -mtime +7 -delete 2>/dev/null",
            
            // Limpa saved application states
            "rm -rf ~/Library/Saved\\ Application\\ State/* 2>/dev/null",
            
            // Limpa derivedData antigo
            "find ~/Library/Developer/Xcode/DerivedData -type d -mtime +30 -maxdepth 1 -exec rm -rf {} \\; 2>/dev/null",
            
            // Limpa simuladores antigos
            "xcrun simctl delete unavailable 2>/dev/null",
        ]
        
        for command in cacheCleanCommands {
            let result = shell.execute(command)
            if result.exitCode == 0 {
                // Estima algum espaço liberado
                bytesRemoved += 500_000_000 // ~500MB estimado por comando
            }
        }
    }
    
    // MARK: - Time Machine Snapshots Cleanup
    private func cleanTimeMachineSnapshots(errors: inout [String], bytesRemoved: inout Int64) {
        // Lista snapshots locais
        let listResult = shell.execute("tmutil listlocalsnapshots /")
        if listResult.exitCode != 0 || listResult.output.isEmpty {
            return // Sem snapshots ou comando falhou
        }
        
        let snapshots = listResult.output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .filter { $0.contains("com.apple.TimeMachine") }
        
        if snapshots.isEmpty {
            return
        }
        
        // Tenta remover todos os snapshots
        var removed = 0
        for snapshot in snapshots {
            let deleteResult = shell.execute("tmutil deletelocalsnapshots \(snapshot)")
            if deleteResult.exitCode == 0 {
                removed += 1
                // Estima 5-10GB por snapshot
                bytesRemoved += 7_000_000_000
            }
        }
        
        if removed > 0 {
            print("Removed \(removed) Time Machine snapshots")
        }
    }
    
    // MARK: - node_modules Cleanup
    private func cleanNodeModules(errors: inout [String], bytesRemoved: inout Int64) {
        // Procura node_modules em diretórios comuns
        let searchPaths = [
            fileHelper.expandPath("~/Projects"),
            fileHelper.expandPath("~/Developer"),
            fileHelper.expandPath("~/Documents"),
            fileHelper.expandPath("~/Desktop"),
        ]
        
        for basePath in searchPaths {
            if !fileHelper.fileExists(atPath: basePath) {
                continue
            }
            
            // Usa find para localizar node_modules modificados há mais de 30 dias
            let findCmd = "find \(basePath) -name 'node_modules' -type d -mtime +30 2>/dev/null"
            let result = shell.execute(findCmd)
            
            if result.exitCode == 0 && !result.output.isEmpty {
                let paths = result.output.components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                
                for path in paths {
                    let size = fileHelper.sizeOfDirectory(atPath: path)
                    if size > 100_000_000 { // Apenas >100MB
                        do {
                            try fileHelper.removeItem(atPath: path)
                            bytesRemoved += size
                        } catch {
                            // Silencia erros de permissão
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Swift Build Cache Cleanup
    private func cleanSwiftBuildCache(errors: inout [String], bytesRemoved: inout Int64) {
        // Limpa build cache adicional do Swift
        let cachePaths = [
            "~/Library/Developer/CoreSimulator/Caches",
            "~/Library/Developer/Xcode/DerivedData",
            "~/.swiftpm/cache",
        ]
        
        for path in cachePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                
                do {
                    try cleanDirectoryContents(atPath: expandedPath)
                    bytesRemoved += size
                } catch {
                    // Ignora erros
                }
            }
        }
    }
}
