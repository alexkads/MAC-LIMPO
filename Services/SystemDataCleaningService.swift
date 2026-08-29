import Foundation

/// `@unchecked Sendable`: o service é imutável (só constantes e singletons
/// thread-safe), e o clean paralelo despacha trabalho para o pool do GCD.
final class SystemDataCleaningService: BaseCleaningService, CleaningService, @unchecked Sendable {
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

        // === APPLE AI & SYSTEM CACHES (ALTO IMPACTO) ===
        ("Siri TTS Cache", "~/Library/Caches/SiriTTS", false),
        ("Call Intelligence Cache", "~/Library/Caches/com.apple.callintelligenced", false),
        ("GeoServices Cache", "~/Library/Caches/GeoServices", false),
        ("Apple Parse Cache", "~/Library/Caches/com.apple.parsecd", false),
        ("Apple Help Cache", "~/Library/Caches/com.apple.helpd", false),
        ("App Store Cache", "~/Library/Caches/com.apple.appstoreagent", false),

        // === LEGACY & MISC ===
        ("Speech/Dictation", "~/Library/Speech", false),
        ("Dictionaries", "~/Library/Dictionaries", false),

        // === FONT E SISTEMA ===
        ("Font Caches", "~/Library/Caches/com.apple.FontRegistry", false),
        ("Spotlight Cache", "~/Library/Caches/com.apple.iconservices.store", false),
        ("Metadata", "~/Library/Caches/Metadata", false),
        // Índice do CoreSpotlight — o Spotlight reindexa depois
        ("Spotlight Index", "~/Library/Metadata/CoreSpotlight", false),

        // === DOWNLOAD E SAVED STATE ===
        ("Saved Application State", "~/Library/Saved Application State", false),

        // === TIME MACHINE (ALTO IMPACTO - COM CONFIRMAÇÃO) ===
        ("Time Machine Local Snapshots", "/.MobileBackups", true)
    ]

    /// Caches pertencentes ao root, removidos em bloco com um único pedido de
    /// senha (mesmo padrão AppleScript dos snapshots do Time Machine). Só no
    /// modo agressivo, para o prompt de senha não surpreender numa limpeza comum.
    /// Ambos são regeneráveis: o Options+ re-baixa os depots e o CoreSimulator
    /// reconstrói o dyld cache no próximo boot de simulador.
    private let rootOwnedCachePaths: [(name: String, path: String)] = [
        ("Logi Options+ depots", "/Library/Application Support/Logi/LogiOptionsPlus/depots"),
        ("Simulator dyld cache", "/Library/Developer/CoreSimulator/Caches/dyld")
    ]

    /// Paths adicionais para scan de node_modules e arquivos grandes
    private let scanOnlyPaths = [
        ("node_modules folders", "node_modules"),
        (".npm cache", "~/.npm"),
        (".yarn cache", "~/.yarn/cache"),
        ("pip cache", "~/Library/Caches/pip")
    ]

    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []

        progress?("Scanning \(systemPaths.count) system locations...")

        // Expande wildcards antes (expansão rasa, barata) e achata em unidades
        // (índice da entrada, path concreto) para medir TUDO em paralelo — em
        // série eram ~50 `du` um após o outro e este era o scan mais lento do
        // app. O paralelismo real é limitado pelo duGate global do helper.
        var flat: [(index: Int, path: String)] = []
        for (index, entry) in systemPaths.enumerated() {
            let expanded = fileHelper.expandPath(entry.1)
            let paths = entry.1.contains("*") ? Self.expandGlob(expanded) : [expanded]
            for path in paths {
                flat.append((index, path))
            }
        }

        let sizesByEntry: [Int: Int64] = await withTaskGroup(of: (Int, Int64).self) { group in
            for unit in flat {
                group.addTask {
                    guard self.fileHelper.fileExists(atPath: unit.path) else { return (unit.index, 0) }
                    return await (unit.index, self.fileHelper.sizeOfDirectoryAsync(atPath: unit.path))
                }
            }
            var accumulated: [Int: Int64] = [:]
            for await (index, size) in group {
                accumulated[index, default: 0] += size
            }
            return accumulated
        }

        for (index, entry) in systemPaths.enumerated() {
            let size = sizesByEntry[index] ?? 0
            if size > 0 {
                totalSize += size
                items.append("\(entry.0): \(fileHelper.formatBytes(size))")
            }
        }

        // Caches root-owned (limpos só no modo agressivo, com senha de admin)
        for (name, path) in rootOwnedCachePaths where fileHelper.fileExists(atPath: path) {
            let size = await fileHelper.sizeOfDirectoryAsync(atPath: path)
            guard size > 0 else { continue }
            if CleaningOptions.shared.aggressiveMode {
                totalSize += size
                items.append("\(name): \(fileHelper.formatBytes(size))")
            } else {
                items.append("\(name): \(fileHelper.formatBytes(size)) (aggressive mode only)")
            }
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
        let freeBefore = fileHelper.availableDiskSpace()
        var errors: [String] = []

        // Achata os alvos (glob raso, sempre limpa CONTEÚDO — nunca remove o
        // diretório pai) e limpa em paralelo, espelhando o scan. O cleanGate
        // limita as remoções simultâneas para não saturar o disco.
        var targets: [String] = []
        for (_, path, requiresConfirmation) in systemPaths where !requiresConfirmation {
            let expanded = fileHelper.expandPath(path)
            let paths = path.contains("*") ? Self.expandGlob(expanded) : [expanded]
            targets.append(contentsOf: paths.filter { fileHelper.fileExists(atPath: $0) })
        }

        var (bytesRemoved, filesRemoved) = await withTaskGroup(of: (Int64, Int).self) { group in
            for target in targets {
                group.addTask { await self.cleanDirectorySafelyAsync(atPath: target) }
            }
            var bytes: Int64 = 0
            var files = 0
            for await (size, count) in group {
                bytes += size
                files += count
            }
            return (bytes, files)
        }

        // Limpa cache do sistema com comandos seguros
        cleanSystemCaches(errors: &errors, bytesRemoved: &bytesRemoved)

        // Snapshots do Time Machine e purge liberam espaço que não passa pelos
        // nossos contadores (e nada aqui vai para a Lixeira), então o delta real
        // de espaço livre é a medida honesta — usa o maior dos dois em vez das
        // estimativas fabricadas que este service somava antes.
        let freedDelta = fileHelper.availableDiskSpace() - freeBefore
        bytesRemoved = max(bytesRemoved, freedDelta)

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

    /// Teto de limpezas de diretório simultâneas — remoção é pesada de I/O.
    private static let cleanGate = AsyncSemaphore(value: 4)

    /// Versão assíncrona de `cleanDirectorySafely`: roda a remoção (bloqueante)
    /// no pool do GCD, com o `cleanGate` limitando a concorrência global.
    private func cleanDirectorySafelyAsync(atPath path: String) async -> (Int64, Int) {
        await Self.cleanGate.acquire()
        defer { Self.cleanGate.release() }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.cleanDirectorySafely(atPath: path))
            }
        }
    }

    /// Limpa o conteúdo de um diretório de forma segura. Mede cada filho de
    /// primeiro nível (enumerador com atributos pré-buscados: um stat por
    /// arquivo) e o remove de uma vez — ordens de grandeza menos syscalls que
    /// apagar arquivo por arquivo. Se a remoção do filho falhar (permissão),
    /// cai para a varredura arquivo a arquivo só nele, preservando o
    /// comportamento antigo de limpar o que der e ignorar o resto.
    private func cleanDirectorySafely(atPath path: String) -> (bytesRemoved: Int64, filesRemoved: Int) {
        var totalBytes: Int64 = 0
        var totalFiles = 0

        for child in fileHelper.contentsOfDirectory(atPath: path) {
            let childPath = (path as NSString).appendingPathComponent(child)
            let (size, count) = Self.measureFiles(atPath: childPath)
            if (try? FileManager.default.removeItem(atPath: childPath)) != nil {
                totalBytes += size
                totalFiles += count
            } else {
                let (bytes, files) = removeFilesIndividually(atPath: childPath)
                totalBytes += bytes
                totalFiles += files
            }
        }

        return (totalBytes, totalFiles)
    }

    /// Tamanho total e nº de arquivos regulares sob um path (o próprio arquivo,
    /// se não for diretório), com atributos pré-buscados na enumeração.
    private static func measureFiles(atPath path: String) -> (Int64, Int) {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return (0, 0) }

        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard isDir.boolValue else {
            let attrs = try? fileManager.attributesOfItem(atPath: path)
            return ((attrs?[.size] as? Int64) ?? 0, 1)
        }

        var bytes: Int64 = 0
        var files = 0
        let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: Array(keys)
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            bytes += Int64(values.fileSize ?? 0)
            files += 1
        }
        return (bytes, files)
    }

    /// Fallback para diretórios parcialmente protegidos: remove arquivo a
    /// arquivo, ignorando erros de permissão silenciosamente.
    private func removeFilesIndividually(atPath path: String) -> (Int64, Int) {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        var toRemove: [(path: String, size: Int64)] = []

        let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: Array(keys)
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            toRemove.append((fileURL.path, Int64(values.fileSize ?? 0)))
        }

        var totalBytes: Int64 = 0
        var totalFiles = 0
        for (filePath, size) in toRemove where (try? fileManager.removeItem(atPath: filePath)) != nil {
            totalBytes += size
            totalFiles += 1
        }
        return (totalBytes, totalFiles)
    }

    /// Expande um padrão com "*" listando apenas o nível de cada curinga —
    /// nunca enumera a árvore inteira. A versão antiga enumerava recursivamente
    /// a base (ex.: ~/Library/Containers, que tem milhões de nós por causa de
    /// Docker/WhatsApp) e levava MINUTOS por padrão; a expansão rasa custa
    /// alguns readdir. Componentes parciais ("V*") casam via fnmatch.
    static func expandGlob(_ pattern: String) -> [String] {
        guard pattern.contains("*") else { return [pattern] }

        let helper = FileSystemHelper.shared
        var paths = ["/"]
        for component in pattern.split(separator: "/").map(String.init) {
            var next: [String] = []
            if component.contains("*") {
                for base in paths {
                    for child in helper.contentsOfDirectory(atPath: base)
                        where fnmatch(component, child, 0) == 0
                    {
                        next.append((base as NSString).appendingPathComponent(child))
                    }
                }
            } else {
                for base in paths {
                    let candidate = (base as NSString).appendingPathComponent(component)
                    if helper.fileExists(atPath: candidate) {
                        next.append(candidate)
                    }
                }
            }
            paths = next
            if paths.isEmpty { break }
        }
        return paths
    }

    private func getTimeMachineSnapshots() -> String? {
        let result = shell.execute("tmutil listlocalsnapshots /")
        if result.exitCode == 0, !result.output.isEmpty {
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

        // 2. Limpa Font Cache (o espaço real liberado entra pelo delta de
        //    espaço livre medido no clean(); nada de estimativas fabricadas)
        _ = shell.execute("atsutil databases -removeUser")
        _ = shell.execute("atsutil server -shutdown")
        _ = shell.execute("atsutil server -ping")

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

        // 10. Caches root-owned (modo agressivo; um único prompt de senha)
        cleanRootOwnedCaches(errors: &errors, bytesRemoved: &bytesRemoved)
    }

    // MARK: - Root-owned Caches (admin)

    private func cleanRootOwnedCaches(errors: inout [String], bytesRemoved: inout Int64) {
        guard CleaningOptions.shared.aggressiveMode else { return }

        var toRemove: [(path: String, size: Int64)] = []
        for (_, path) in rootOwnedCachePaths where fileHelper.fileExists(atPath: path) {
            let size = fileHelper.sizeOfDirectory(atPath: path)
            if size > 0 {
                toRemove.append((path, size))
            }
        }
        guard !toRemove.isEmpty else { return }

        // Um único `do shell script … with administrator privileges` remove
        // todos os paths com um só pedido de senha. Paths são constantes do
        // código (nunca entrada do usuário).
        let quoted = toRemove.map { "\\\"\($0.path)\\\"" }.joined(separator: " ")
        let appleScript = """
        do shell script "rm -rf \(quoted)" with administrator privileges
        """
        let result = shell.execute("osascript -e '\(appleScript)'")
        if result.exitCode == 0 {
            bytesRemoved += toRemove.reduce(0) { $0 + $1.size }
            logger.log("Caches root-owned removidos (\(toRemove.count) paths)", level: .info)
        } else if !result.error.contains("User canceled") {
            errors.append("Failed to clean root-owned caches")
        }
    }

    // MARK: - Application Support Cleanup

    private func cleanApplicationSupport(errors _: inout [String], bytesRemoved: inout Int64) {
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
            ("Postman/proxy", "Postman Proxy Cache")
        ]

        for (relativePath, _) in cachesToClean {
            let pattern = (appSupportPath as NSString).appendingPathComponent(relativePath)

            if pattern.contains("*") {
                // Usa find para wildcards
                let findCmd = "find \(pattern.replacingOccurrences(of: "*", with: "\\*")) -type d 2>/dev/null"
                let result = shell.execute(findCmd)

                if result.exitCode == 0, !result.output.isEmpty {
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

    private func forcePurgeableSpace(errors _: inout [String], bytesRemoved _: inout Int64) {
        // Escrever 5 GB com dd desgasta o SSD e demora — só faz sentido quando
        // o usuário pediu limpeza agressiva. O que o purge liberar aparece no
        // delta de espaço livre medido no clean() (nada de +10 GB estimados).
        guard CleaningOptions.shared.aggressiveMode else { return }

        let tempPath = "/tmp/maclimpo_purge_\(Int(Date().timeIntervalSince1970)).tmp"

        // Tenta criar arquivo de 5GB (força o sistema a liberar purgeable)
        _ = shell.execute("dd if=/dev/zero of=\(tempPath) bs=1m count=5000 2>/dev/null")
        _ = shell.execute("rm -f \(tempPath)")
    }

    // MARK: - Time Machine with Sudo

    private func cleanTimeMachineSnapshotsWithSudo(errors _: inout [String], bytesRemoved _: inout Int64) {
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

        // Extrai as datas e apaga TODAS num único `do shell script` — um só
        // pedido de senha, em vez do prompt por snapshot que havia antes.
        // O espaço liberado entra pelo delta de espaço livre no clean().
        let dates = snapshots.compactMap { snapshot -> String? in
            let components = snapshot.components(separatedBy: ".")
            guard components.count >= 4 else { return nil }
            return components[3]
        }
        guard !dates.isEmpty else { return }

        let deleteCommands = dates
            .map { "tmutil deletelocalsnapshots \($0)" }
            .joined(separator: "; ")
        let appleScript = """
        do shell script "\(deleteCommands)" with administrator privileges
        """

        let result = shell.execute("osascript -e '\(appleScript)'")
        if result.exitCode == 0 {
            logger.log("Removidos \(dates.count) snapshots do Time Machine", level: .info)
        }
    }

    // MARK: - Shell-based Cache Cleaning

    private func cleanCachesViaShell(errors _: inout [String], bytesRemoved _: inout Int64) {
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
            "xcrun simctl delete unavailable 2>/dev/null"
        ]

        for command in cacheCleanCommands {
            _ = shell.execute(command)
        }
    }

    // MARK: - node_modules Cleanup

    private func cleanNodeModules(errors _: inout [String], bytesRemoved: inout Int64) {
        // Procura node_modules em diretórios comuns
        let searchPaths = [
            fileHelper.expandPath("~/Projects"),
            fileHelper.expandPath("~/Developer"),
            fileHelper.expandPath("~/Documents"),
            fileHelper.expandPath("~/Desktop")
        ]

        for basePath in searchPaths {
            if !fileHelper.fileExists(atPath: basePath) {
                continue
            }

            // Usa find para localizar node_modules modificados há mais de 30 dias
            let findCmd = "find \(basePath) -name 'node_modules' -type d -mtime +30 2>/dev/null"
            let result = shell.execute(findCmd)

            if result.exitCode == 0, !result.output.isEmpty {
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

    private func cleanSwiftBuildCache(errors _: inout [String], bytesRemoved: inout Int64) {
        // Limpa build cache adicional do Swift
        let cachePaths = [
            "~/Library/Developer/CoreSimulator/Caches",
            "~/Library/Developer/Xcode/DerivedData",
            "~/.swiftpm/cache"
        ]

        for path in cachePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                // Conta só o que foi realmente removido (a versão antiga somava
                // o tamanho cheio mesmo quando a remoção falhava no meio).
                let (bytes, _) = cleanDirectorySafely(atPath: expandedPath)
                bytesRemoved += bytes
            }
        }
    }
}
