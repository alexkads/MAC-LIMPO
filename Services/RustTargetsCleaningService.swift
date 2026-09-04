import Foundation

/// Limpa os diretórios `target/` gerados pelo Cargo nos projetos Rust.
///
/// Separado de `ProjectCleaningService` porque um único `target/` costuma ser a
/// maior pasta do disco inteiro (dezenas de GB) e ficava diluído no total de
/// "Project Builds", sem indicar de onde vinha o peso. Tudo aqui é reconstruível
/// com `cargo build` — o próprio cargo marca o diretório com `CACHEDIR.TAG`.
final class RustTargetsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .rustTargets

    /// Raiz varrida em busca de crates. Mesma convenção do `ProjectCleaningService`.
    private let projectRoot = "~/Projects"

    /// Abaixo disso o diretório não paga o ruído de aparecer na lista.
    private let minimumSize: Int64 = 50 * 1024 * 1024

    /// Diretórios que nunca contêm um crate e custam caro para percorrer — um
    /// único `node_modules` tem centenas de milhares de arquivos. Pular esses é
    /// a maior parte do ganho de tempo do scan. (Os ocultos, como `.git`, já
    /// saem por `skipsHiddenFiles`.)
    private let prunedDirectories: Set<String> = [
        "node_modules", "Pods", "DerivedData", "dist", "build", "vendor"
    ]

    /// Um `target/` do cargo já medido.
    private struct Candidate {
        let path: String
        let size: Int64
        /// Caminho relativo à raiz varrida, para exibição.
        let displayName: String
    }

    // MARK: - Descoberta

    /// Enumera `projectRoot` atrás de `target/` com um `Cargo.toml` irmão.
    /// Compartilhado por `scan` e `clean` para os dois nunca divergirem.
    private func findTargets(progress: ((String) -> Void)?) -> [Candidate] {
        let root = fileHelper.expandPath(projectRoot)
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var candidates: [Candidate] = []

        while let url = enumerator.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            let name = url.lastPathComponent
            guard name == "target" else {
                if prunedDirectories.contains(name) { enumerator.skipDescendants() }
                continue
            }

            // Nada dentro de um target/ interessa, seja ele do cargo ou não.
            enumerator.skipDescendants()

            // Só é do cargo se houver um manifesto ao lado — senão pode ser um
            // "target" qualquer de outro ecossistema.
            let parent = url.deletingLastPathComponent()
            guard fileManager.fileExists(atPath: parent.appendingPathComponent("Cargo.toml").path) else { continue }

            let displayName = "\(parent.lastPathComponent)/target"
            progress?("Measuring \(displayName)...")

            let size = fileHelper.sizeOfDirectory(atPath: url.path)
            guard size >= minimumSize else { continue }

            candidates.append(Candidate(path: url.path, size: size, displayName: displayName))
        }

        return candidates.sorted { $0.size > $1.size }
    }

    /// O cargo protege o diretório de build com um `flock(2)` em
    /// `target/<perfil>/.cargo-lock` — é o lock que produz o "Blocking waiting
    /// for file lock" dele. Se não conseguimos tomar esse lock, há um
    /// `cargo build/test` rodando e apagar o diretório agora corromperia o build
    /// em curso.
    private func isBuildInProgress(targetPath: String) -> Bool {
        let fileManager = FileManager.default
        let profiles = (try? fileManager.contentsOfDirectory(atPath: targetPath)) ?? []

        for profile in profiles {
            let lockPath = ((targetPath as NSString).appendingPathComponent(profile) as NSString)
                .appendingPathComponent(".cargo-lock")
            guard fileManager.fileExists(atPath: lockPath) else { continue }

            let descriptor = open(lockPath, O_RDONLY)
            guard descriptor >= 0 else { continue }
            defer { close(descriptor) }

            if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
                if errno == EWOULDBLOCK { return true }
                continue
            }
            // Conseguimos o lock: ninguém está construindo. Devolve na hora.
            flock(descriptor, LOCK_UN)
        }

        return false
    }

    // MARK: - CleaningService

    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        logger.log("Iniciando escaneamento de targets Rust", level: .info)
        progress?("Scanning Rust projects...")

        let candidates = findTargets(progress: progress)
        let totalSize = candidates.reduce(Int64(0)) { $0 + $1.size }

        let items = candidates.map { candidate -> String in
            let busy = isBuildInProgress(targetPath: candidate.path)
            let note = busy ? " — build running, will be skipped" : ""
            return "\(candidate.displayName) (\(fileHelper.formatBytes(candidate.size)))\(note)"
        }

        logger.log(
            "Escaneamento de targets Rust concluído: \(fileHelper.formatBytes(totalSize)) em \(candidates.count) projeto(s)",
            level: .info
        )

        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: candidates.count,
            items: items
        )
    }

    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []

        logger.log("Iniciando limpeza de targets Rust", level: .info)

        for candidate in findTargets(progress: nil) {
            if isBuildInProgress(targetPath: candidate.path) {
                errors.append("Skipped \(candidate.displayName): a Cargo build is running")
                logger.log("Pulando \(candidate.path): build do cargo em andamento", level: .warning)
                continue
            }

            do {
                try fileHelper.removeItem(atPath: candidate.path)
                bytesRemoved += candidate.size
                filesRemoved += 1
                logger.log("Removido target Rust: \(candidate.path)", level: .info)
            } catch {
                errors.append("Failed to clean \(candidate.displayName): \(error.localizedDescription)")
                logger.log("Falha ao remover \(candidate.path): \(error)", level: .error)
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
