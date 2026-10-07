import Foundation

/// Limpa os diretórios `target/` gerados pelo Cargo nos projetos Rust.
///
/// Separado de `ProjectCleaningService` porque um único `target/` costuma ser a
/// maior pasta do disco inteiro (dezenas de GB) e ficava diluído no total de
/// "Project Builds", sem indicar de onde vinha o peso. Tudo aqui é reconstruível
/// com `cargo build` — o próprio cargo marca o diretório com `CACHEDIR.TAG`.
final class RustTargetsCleaningService: BaseCleaningService, CleaningService, @unchecked Sendable {
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

    /// Lixeira por padrão (reversível); os testes desligam para não encher a Lixeira real.
    private let useTrash: Bool

    init(useTrash: Bool = true) {
        self.useTrash = useTrash
    }

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
    ///
    /// A varredura de diretórios bloqueia, então roda fora do pool cooperativo; os
    /// tamanhos são medidos por `sizeOfDirectoryAsync`, atrás do `duGate` global.
    private func findTargets(progress: (@Sendable (String) -> Void)?) async -> [Candidate] {
        let found = await runBlocking { self.discoverTargetDirectories() }

        var candidates: [Candidate] = []
        for (path, displayName) in found {
            progress?(String(localized: "Measuring \(displayName)…"))
            let size = await fileHelper.sizeOfDirectoryAsync(atPath: path)
            guard size >= minimumSize else { continue }
            candidates.append(Candidate(path: path, size: size, displayName: displayName))
        }

        return candidates.sorted { $0.size > $1.size }
    }

    /// Só descoberta (sem medir tamanho): pares (caminho do `target/`, nome de exibição).
    private func discoverTargetDirectories() -> [(path: String, displayName: String)] {
        let root = fileHelper.expandPath(projectRoot)
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [(String, String)] = []

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

            found.append((url.path, "\(parent.lastPathComponent)/target"))
        }

        return found
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

    func scan(progress: (@Sendable (String) -> Void)?) async -> ScanResult {
        logger.log("Iniciando escaneamento de targets Rust", level: .info)
        progress?(String(localized: "Scanning Rust projects…"))

        let candidates = await findTargets(progress: progress)
        let totalSize = candidates.reduce(Int64(0)) { $0 + $1.size }

        let mounts = candidates.isEmpty ? [:] : await dockerMountPoints()
        let items = candidates.map { candidate -> String in
            var note = ""
            if isBuildInProgress(targetPath: candidate.path) {
                note = " — build running, will be skipped"
            } else if let container = mounts[candidate.path] {
                note = " — Docker mount point (\(container)), contents only"
            }
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

        let candidates = await findTargets(progress: nil)
        let mounts = candidates.isEmpty ? [:] : await dockerMountPoints()

        for candidate in candidates {
            if isBuildInProgress(targetPath: candidate.path) {
                errors.append(String(localized: "Skipped \(candidate.displayName): a Cargo build is running"))
                logger.log("Pulando \(candidate.path): build do cargo em andamento", level: .warning)
                continue
            }

            if let container = mounts[candidate.path] {
                logger.log(
                    "\(candidate.path) é ponto de montagem do contêiner \(container); limpando só o conteúdo",
                    level: .info
                )
            }

            // Esvazia o `target/` em vez de removê-lo. O cargo usa a pasta vazia
            // sem problema, e ela pode ser ponto de montagem de um volume Docker
            // (`./backend:/app` + volume em `/app/target`): enquanto o contêiner
            // roda, o virtiofs mantém a pasta aberta e removê-la dá EACCES, o que
            // marcava a limpeza como falha mesmo com todo o conteúdo apagado.
            let path = candidate.path
            let failures = await runBlocking { self.emptyDirectory(atPath: path) }
            let remaining = await fileHelper.sizeOfDirectoryAsync(atPath: candidate.path)
            let freed = max(0, candidate.size - remaining)
            bytesRemoved += freed

            if failures.isEmpty {
                filesRemoved += 1
                logger.log("Esvaziado target Rust: \(candidate.path)", level: .info)
            } else {
                errors.append(
                    String(localized: "Partially cleaned \(candidate.displayName): \(failures.count) item(s) could not be removed")
                )
                for failure in failures {
                    logger.log("Falha ao remover \(failure)", level: .error)
                }
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

    // MARK: - Remoção

    /// Remove cada item dentro de `path`, mantendo a própria pasta. Prefere a
    /// Lixeira e cai para remoção definitiva só se ela recusar. Devolve os
    /// caminhos que não puderam ser removidos.
    func emptyDirectory(atPath path: String) -> [String] {
        var failures: [String] = []
        let fileManager = FileManager.default
        // Inclui ocultos (`.rustc_info.json`, `.cargo-lock`…).
        let children = (try? fileManager.contentsOfDirectory(atPath: path)) ?? []

        for child in children {
            let childPath = (path as NSString).appendingPathComponent(child)
            if useTrash, fileHelper.trashItem(atPath: childPath) { continue }
            do {
                try fileHelper.removeItem(atPath: childPath)
            } catch {
                failures.append(childPath)
            }
        }
        return failures
    }

    // MARK: - Docker

    /// Caminhos do Mac que servem de ponto de montagem para contêineres em
    /// execução → nome do contêiner. Vazio se o Docker não estiver rodando.
    private func dockerMountPoints() async -> [String: String] {
        await runBlocking {
            let ids = self.shell.run("/usr/bin/env", ["docker", "ps", "-q"], timeout: 15)
            let containerIds = ids.output.split(whereSeparator: \.isNewline).map(String.init)
            guard ids.exitCode == 0, !containerIds.isEmpty else { return [:] }

            let format = "{{$n := .Name}}{{range .Mounts}}{{$n}}|{{.Type}}|{{.Source}}|{{.Destination}}\n{{end}}"
            let inspect = self.shell.run(
                "/usr/bin/env",
                ["docker", "inspect", "--format", format] + containerIds,
                timeout: 15
            )
            guard inspect.exitCode == 0 else { return [:] }
            return Self.hostMountPoints(fromInspect: inspect.output)
        }
    }

    /// Interpreta linhas `nome|tipo|origem|destino` do `docker inspect` e devolve
    /// os caminhos do Mac sobre os quais o Docker monta algo. Função pura (testável).
    ///
    /// Um volume montado em `/app/target` com o projeto em bind mount
    /// `~/proj:/app` cai em `~/proj/target` no Mac — é a pasta que o Docker
    /// precisa manter. A origem de bind mounts às vezes vem com o prefixo
    /// `/host_mnt` da VM, que é removido.
    static func hostMountPoints(fromInspect output: String) -> [String: String] {
        struct Mount {
            let container: String
            let type: String
            let source: String
            let destination: String
        }

        let mounts: [Mount] = output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4 else { return nil }
            var source = fields[2]
            if source.hasPrefix("/host_mnt/") { source.removeFirst("/host_mnt".count) }
            let container = fields[0].hasPrefix("/") ? String(fields[0].dropFirst()) : fields[0]
            return Mount(container: container, type: fields[1], source: source, destination: fields[3])
        }

        var result: [String: String] = [:]
        for bind in mounts where bind.type == "bind" {
            for other in mounts where other.container == bind.container && other.destination != bind.destination {
                let prefix = bind.destination.hasSuffix("/") ? bind.destination : bind.destination + "/"
                guard other.destination.hasPrefix(prefix) else { continue }
                let relative = String(other.destination.dropFirst(prefix.count))
                result[(bind.source as NSString).appendingPathComponent(relative)] = bind.container
            }
        }
        return result
    }
}
