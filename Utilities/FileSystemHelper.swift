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
    func sizeOfDirectory(atPath path: String) -> Int64 {
        guard fileManager.fileExists(atPath: path) else { return 0 }

        // Usa `du` por performance. Passa o path como argumento (sem shell) para
        // não quebrar em paths com aspas/espaços. parseDuKilobytes ignora a coluna
        // do path na saída "1234\t/path".
        let result = ShellExecutor.shared.run("/usr/bin/du", ["-sk", path], timeout: Self.sizeMeasurementTimeout)
        if let bytes = Self.parseDuKilobytes(result.output) {
            return bytes
        }

        // Fallback para método lento se du falhar
        return sizeOfDirectoryFallback(atPath: path)
    }

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
    func sizesOfDirectories(atPaths paths: [String], batchSize: Int = 48) -> [String: Int64] {
        guard !paths.isEmpty else { return [:] }
        var sizes: [String: Int64] = [:]

        for batch in stride(from: 0, to: paths.count, by: batchSize).map({
            Array(paths[$0 ..< min($0 + batchSize, paths.count)])
        }) {
            // Orçamento proporcional ao lote: um `du` por path tinha 120s cada,
            // então um lote de 48 não pode herdar o mesmo teto de um path só.
            let timeout = min(Self.batchMeasurementCeiling, 30 + Double(batch.count) * 4)
            let result = ShellExecutor.shared.run("/usr/bin/du", ["-sk"] + batch, timeout: timeout)
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
    func sizeOfDirectoryAsync(atPath path: String) async -> Int64 {
        await Self.duGate.acquire()
        defer { Self.duGate.release() }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.sizeOfDirectory(atPath: path))
            }
        }
    }

    /// Versão assíncrona de `sizesOfDirectories`, fora do pool cooperativo e
    /// atrás do mesmo `duGate` — um lote ocupa um único slot, não um por path.
    func sizesOfDirectoriesAsync(atPaths paths: [String], batchSize: Int = 48) async -> [String: Int64] {
        guard !paths.isEmpty else { return [:] }
        await Self.duGate.acquire()
        defer { Self.duGate.release() }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.sizesOfDirectories(atPaths: paths, batchSize: batchSize))
            }
        }
    }

    /// Soma dos tamanhos de `paths` medidos em lote. Conveniência para os
    /// services que só querem o total de um alvo com muitos paths concretos.
    func totalSizeOfDirectoriesAsync(atPaths paths: [String]) async -> Int64 {
        await sizesOfDirectoriesAsync(atPaths: paths).values.reduce(0, +)
    }

    // Fallback: Calcula o tamanho recursivamente (lento)
    private func sizeOfDirectoryFallback(atPath path: String) -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(atPath: path) {
            while let file = enumerator.nextObject() as? String {
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
           let importantAvailable = values.volumeAvailableCapacityForImportantUsage {
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
