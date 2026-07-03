import Foundation
import os.log

class FileSystemHelper {
    static let shared = FileSystemHelper()
    private let fileManager = FileManager.default

    /// Calcula o tamanho de um diretório usando du (muito mais rápido)
    func sizeOfDirectory(atPath path: String) -> Int64 {
        guard fileManager.fileExists(atPath: path) else { return 0 }

        // Tenta usar du primeiro para performance
        let command = "du -sk '\(path)' | cut -f1"
        let result = ShellExecutor.shared.execute(command, timeout: 5)
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
        let firstToken = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first.map(String.init) ?? trimmed
        guard let kb = Int64(firstToken) else { return nil }
        return kb * 1024 // KB -> bytes
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
            // Se falhar (ex: permissão ou locked), tenta forçar via shell
            let command = "rm -rf '\(path)'"
            let result = ShellExecutor.shared.execute(command)

            if result.exitCode != 0 {
                // Se ambos falharem, retorna o erro original
                throw error
            }
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

    /// Obtém espaço disponível em disco
    func availableDiskSpace() -> Int64 {
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSize = systemAttributes[.systemFreeSize] as? Int64 {
                return freeSize
            }
        } catch {
            return 0
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
            return 0
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
