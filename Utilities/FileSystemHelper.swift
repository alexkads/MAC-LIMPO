import Foundation
import os.log

/// Singleton imutável (só mantém um FileManager) — seguro para usar entre threads.
final class FileSystemHelper: @unchecked Sendable {
    static let shared = FileSystemHelper()
    private let fileManager = FileManager.default

    /// Timeout do `du` ao medir tamanho. Precisa ser generoso: pastas grandes
    /// (ex.: imagens do Docker, com dezenas de GB) demoram bem mais que poucos
    /// segundos, e um timeout curto fazia o `du` ser morto e o tamanho virar 0
    /// (subcontagem silenciosa do espaço recuperável).
    static let sizeMeasurementTimeout: TimeInterval = 120

    /// Calcula o tamanho de um diretório usando du (muito mais rápido)
    func sizeOfDirectory(atPath path: String, cancellation: CancellationFlag? = nil) -> Int64 {
        guard fileManager.fileExists(atPath: path) else { return 0 }

        // Usa `du` por performance. Passa o path como argumento (sem shell) para
        // não quebrar em paths com aspas/espaços. parseDuKilobytes ignora a coluna
        // do path na saída "1234\t/path".
        let du = Self.duInvocation(["-sk", path])
        let result = ShellExecutor.shared.run(
            du.launchPath, du.arguments, timeout: Self.sizeMeasurementTimeout, cancellation: cancellation
        )
        if let bytes = Self.parseDuKilobytes(result.output) {
            return bytes
        }

        // Cancelado: o scan foi abandonado, não há a quem entregar a medição.
        if cancellation?.isCancelled == true { return 0 }

        // Timeout do `du` NÃO cai no fallback: o enumerador é mais lento que o
        // `du` e não tem teto, então repetia a varredura que já estourou 120s
        // segurando um dos slots do `duGate`. Com 4 pastas assim o scan inteiro
        // parava e o card ficava girando até reabrir o app.
        if Self.isTimeout(result) {
            Logger.shared.log("du excedeu \(Int(Self.sizeMeasurementTimeout))s: \(path)", level: .warning)
            return 0
        }

        // Fallback para método lento se du falhar (com prazo).
        return sizeOfDirectoryFallback(atPath: path)
    }

    /// Onde está o `taskpolicy` do sistema (nil se não existir).
    private static let taskpolicyPath: String? = {
        let path = "/usr/sbin/taskpolicy"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }()

    /// Monta a chamada do `du` com prioridade baixa de CPU e de disco.
    ///
    /// Medir milhares de `node_modules` lê os metadados de milhões de arquivos
    /// pequenos; com prioridade normal isso disputava o SSD de igual para igual
    /// com builds e com o resto do sistema. Com `taskpolicy -c utility -d utility`
    /// o `du` cede o disco a quem tem prioridade maior e anda quando ele está
    /// livre. Sem o `taskpolicy`, roda o `du` direto.
    static func duInvocation(_ arguments: [String]) -> (launchPath: String, arguments: [String]) {
        guard let taskpolicy = taskpolicyPath else { return ("/usr/bin/du", arguments) }
        return (taskpolicy, ["-c", "utility", "-d", "utility", "/usr/bin/du"] + arguments)
    }

    /// `ShellExecutor` sinaliza timeout com exitCode -1 e esta mensagem.
    static func isTimeout(_ result: (output: String, error: String, exitCode: Int32)) -> Bool {
        result.exitCode == -1 && result.error.contains("timed out")
    }

    /// Prazo do fallback lento — melhor subcontar que travar o scan.
    static let fallbackMeasurementDeadline: TimeInterval = 30

    /// Converte a saída de `du -sk` (KB) em bytes. Função pura (testável).
    /// Aceita saída com espaços/quebras de linha; retorna nil se não for numérica.
    static func parseDuKilobytes(_ output: String) -> Int64? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        // `du -sk 'path' | cut -f1` pode vir com espaços residuais; pega o primeiro token.
        let firstToken = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first
            .map(String.init) ?? trimmed
        guard let kb = Int64(firstToken) else { return nil }
        return kb * 1024 // KB -> bytes
    }

    /// Mede vários diretórios numa única invocação de `du -sk`.
    ///
    /// `du` aceita N paths e imprime uma linha "KB\tpath" por argumento. Medir um
    /// path por processo era o gargalo real do scan: os globs de container
    /// (`~/Library/Containers/*/…`) chegam a ~800 paths cada, o que virava
    /// ~1700 processos `du` numa categoria só — minutos de espera com o card
    /// preso no spinner. Em lotes de `batchSize` isso cai para dezenas.
    ///
    /// Paths ilegíveis não aparecem na saída (o `du` reclama em stderr); eles
    /// simplesmente ficam de fora do dicionário retornado.
    func sizesOfDirectories(
        atPaths paths: [String],
        batchSize: Int = 48,
        cancellation: CancellationFlag? = nil
    ) -> [String: Int64] {
        guard !paths.isEmpty else { return [:] }
        var sizes: [String: Int64] = [:]

        for batch in stride(from: 0, to: paths.count, by: batchSize).map({
            Array(paths[$0 ..< min($0 + batchSize, paths.count)])
        }) {
            // Scan abandonado: para entre lotes em vez de medir o resto.
            if cancellation?.isCancelled == true { break }
            // Orçamento proporcional ao lote: um `du` por path tinha 120s cada,
            // então um lote de 48 não pode herdar o mesmo teto de um path só.
            let timeout = min(Self.batchMeasurementCeiling, 30 + Double(batch.count) * 4)
            let du = Self.duInvocation(["-sk"] + batch)
            let result = ShellExecutor.shared.run(
                du.launchPath,
                du.arguments,
                timeout: timeout,
                cancellation: cancellation
            )
            if Self.isTimeout(result) {
                // O lote inteiro se perde (saída parcial é descartada no timeout).
                Logger.shared.log("du em lote excedeu \(Int(timeout))s (\(batch.count) paths)", level: .warning)
            }
            for (path, bytes) in Self.parseDuBatch(result.output) {
                sizes[path, default: 0] += bytes
            }
        }

        return sizes
    }

    /// Teto de tempo para um lote inteiro do `du`.
    static let batchMeasurementCeiling: TimeInterval = 240

    /// Converte a saída multi-linha de `du -sk p1 p2 …` em `path -> bytes`.
    /// Função pura (testável). Linhas sem tab ou com KB não numérico são ignoradas.
    static func parseDuBatch(_ output: String) -> [(path: String, bytes: Int64)] {
        var parsed: [(String, Int64)] = []
        for line in output.split(separator: "\n") {
            // "1234\t/algum/path" — o path pode conter espaços, então quebramos
            // só no primeiro tab em vez de tokenizar por whitespace.
            guard let tab = line.firstIndex(of: "\t") else { continue }
            guard let kb = Int64(line[line.startIndex ..< tab].trimmingCharacters(in: .whitespaces)) else { continue }
            let path = String(line[line.index(after: tab)...])
            guard !path.isEmpty else { continue }
            parsed.append((path, kb * 1024))
        }
        return parsed
    }

    /// Teto de `du` simultâneos. Medir tamanho é limitado por I/O num único
    /// disco: acima de um punhado em paralelo o disco satura e nada acelera. Sem
    /// esse teto o problema é pior que lentidão — cada `du` fica bloqueado numa
    /// thread do pool global, o GCD responde criando *mais* threads, e o
    /// fan-out aninhado do scan (várias categorias × dezenas de paths cada)
    /// chegava a 64 `du` de uma vez, travando a varredura inteira.
    private static let duGate = AsyncSemaphore(value: 4)

    /// Versão assíncrona de `sizeOfDirectory`. Roda o `du` (bloqueante) no pool
    /// concorrente do GCD, mas passa por `duGate` primeiro, de modo que no
    /// máximo `duGate` medições rodam ao mesmo tempo por todo o app — não importa
    /// quantas tarefas de scan chamem isto em paralelo.
    ///
    /// Cancelar a `Task` encerra o `du` em andamento (ver `CancellationFlag`).
    func sizeOfDirectoryAsync(atPath path: String) async -> Int64 {
        await Self.duGate.acquire()
        defer { Self.duGate.release() }
        // Cancelada enquanto esperava a vez: não começa a medir.
        if Task.isCancelled { return 0 }
        return await runBlockingCancellable { flag in
            self.sizeOfDirectory(atPath: path, cancellation: flag)
        }
    }

    /// Versão assíncrona de `sizesOfDirectories`, fora do pool cooperativo e
    /// atrás do mesmo `duGate` — um lote ocupa um único slot, não um por path.
    ///
    /// Com `reuseUnchanged`, pastas cuja data de modificação não mudou desde a
    /// última medição (e medidas há menos de `sizeCacheLifetime`) não passam
    /// pelo `du` de novo — ver `DirectorySizeCache`.
    func sizesOfDirectoriesAsync(
        atPaths paths: [String],
        batchSize: Int = 48,
        reuseUnchanged: Bool = false
    ) async -> [String: Int64] {
        guard !paths.isEmpty else { return [:] }

        var sizes: [String: Int64] = [:]
        var toMeasure = paths
        var stamps: [String: Date] = [:]
        if reuseUnchanged {
            toMeasure = []
            for path in paths {
                guard let stamp = Self.modificationDate(ofPath: path) else { continue }
                if let cached = Self.sizeCache.size(for: path, modifiedAt: stamp) {
                    sizes[path] = cached
                } else {
                    stamps[path] = stamp
                    toMeasure.append(path)
                }
            }
            guard !toMeasure.isEmpty else { return sizes }
        }

        await Self.duGate.acquire()
        defer { Self.duGate.release() }
        if Task.isCancelled { return sizes }
        let pending = toMeasure
        let measured = await runBlockingCancellable { flag in
            self.sizesOfDirectories(atPaths: pending, batchSize: batchSize, cancellation: flag)
        }
        for (path, size) in measured {
            sizes[path] = size
            if let stamp = stamps[path] {
                Self.sizeCache.store(size, for: path, modifiedAt: stamp)
            }
        }
        return sizes
    }

    /// Medições reaproveitadas entre scans (`sizesOfDirectoriesAsync(reuseUnchanged:)`).
    static let sizeCache = DirectorySizeCache()

    /// Data de modificação do próprio diretório (nil se não existir).
    static func modificationDate(ofPath path: String) -> Date? {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    /// Soma dos tamanhos de `paths` medidos em lote. Conveniência para os
    /// services que só querem o total de um alvo com muitos paths concretos.
    func totalSizeOfDirectoriesAsync(atPaths paths: [String]) async -> Int64 {
        await sizesOfDirectoriesAsync(atPaths: paths).values.reduce(0, +)
    }

    // Fallback: Calcula o tamanho recursivamente (lento)
    private func sizeOfDirectoryFallback(atPath path: String) -> Int64 {
        var totalSize: Int64 = 0
        let deadline = Date().addingTimeInterval(Self.fallbackMeasurementDeadline)

        if let enumerator = fileManager.enumerator(atPath: path) {
            while let file = enumerator.nextObject() as? String {
                if Date() > deadline {
                    Logger.shared.log("Fallback de tamanho excedeu o prazo: \(path)", level: .warning)
                    break
                }
                let filePath = (path as NSString).appendingPathComponent(file)

                do {
                    let attributes = try fileManager.attributesOfItem(atPath: filePath)
                    if let fileSize = attributes[.size] as? Int64 {
                        totalSize += fileSize
                    }
                } catch {
                    continue
                }
            }
        }

        return totalSize
    }

    /// Remove diretório ou arquivo com fallback para rm -rf
    func removeItem(atPath path: String) throws {
        do {
            try fileManager.removeItem(atPath: path)
        } catch {
            // Se falhar (ex: permissão ou locked), tenta forçar via rm.
            // Path como argumento (sem shell) — seguro para aspas/espaços.
            let result = ShellExecutor.shared.run("/bin/rm", ["-rf", path])

            if result.exitCode != 0 {
                // Se ambos falharem, retorna o erro original
                throw error
            }
        }
    }

    /// Move um item para a Lixeira (reversível). Retorna `true` em caso de sucesso.
    /// Preferível a `removeItem` para limpeza acionada pelo usuário: dá a chance de
    /// restaurar. Falha (retorna false) em volumes/paths sem suporte a Lixeira.
    @discardableResult
    func trashItem(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            Logger.shared.log("Falha ao mover para a Lixeira: \(path) — \(error.localizedDescription)", level: .warning)
            return false
        }
    }

    /// `true` se o item, ou qualquer coisa dentro dele, foi modificado em `cutoff`
    /// ou depois. Para na primeira modificação recente. Na dúvida (atributos ou
    /// subpastas ilegíveis) responde `true`: quem pergunta só apaga o que prova
    /// estar parado. Não segue links simbólicos.
    func hasModifications(since cutoff: Date, atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let modified = values.contentModificationDate else { return true }
        if modified >= cutoff { return true }
        guard values.isDirectory == true, values.isSymbolicLink != true else { return false }

        var unreadable = false
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            errorHandler: { _, _ in
                unreadable = true
                return false
            }
        ) else { return true }
        while let child = enumerator.nextObject() as? URL {
            guard let date = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date < cutoff else { return true }
        }
        return unreadable
    }

    /// Quando o item entrou na pasta onde está (a "Data de Adição" do Finder);
    /// sem esse atributo, a data de criação.
    func dateAdded(atPath path: String) -> Date? {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [
            .addedToDirectoryDateKey,
            .creationDateKey
        ])
        return values?.addedToDirectoryDate ?? values?.creationDate
    }

    /// Lista conteúdo de diretório
    func contentsOfDirectory(atPath path: String) -> [String] {
        do {
            return try fileManager.contentsOfDirectory(atPath: path)
        } catch {
            return []
        }
    }

    /// Verifica se path existe
    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    /// Expande ~ para home directory
    func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Obtém espaço disponível em disco.
    ///
    /// Usa `volumeAvailableCapacityForImportantUsage`, que no APFS reflete o espaço
    /// realmente disponível (incluindo o purgeable que o macOS libera sob demanda) —
    /// o mesmo número que o Finder mostra. Faz fallback para `.systemFreeSize`.
    func availableDiskSpace() -> Int64 {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let importantAvailable = values.volumeAvailableCapacityForImportantUsage
        {
            return importantAvailable
        }
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSize = systemAttributes[.systemFreeSize] as? Int64 {
                return freeSize
            }
        } catch {
            Logger.shared.log("Falha ao ler espaço livre do disco: \(error.localizedDescription)", level: .warning)
        }
        return 0
    }

    /// Obtém tamanho total do disco
    func totalDiskSpace() -> Int64 {
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let totalSize = systemAttributes[.systemSize] as? Int64 {
                return totalSize
            }
        } catch {
            Logger.shared.log("Falha ao ler tamanho total do disco: \(error.localizedDescription)", level: .warning)
        }
        return 0
    }

    /// Formata bytes para string legível
    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Conta arquivos em diretório
    func countFiles(inDirectory path: String) -> Int {
        var count = 0
        if let enumerator = fileManager.enumerator(atPath: path) {
            while enumerator.nextObject() != nil {
                count += 1
            }
        }
        return count
    }
}

// MARK: - Logger movido para Services/Logger.swift
