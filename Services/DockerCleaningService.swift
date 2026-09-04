import Foundation

class DockerCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .docker

    /// `docker system df -v` mede o tamanho de cada volume percorrendo o disco da
    /// VM; num setup grande passa fácil dos 60s padrão.
    private static let inspectionTimeout: TimeInterval = 180

    /// O CLI do `docker` pode estar instalado mas o daemon desligado (Docker Desktop
    /// fechado). Nesse caso os comandos de prune falham com "Cannot connect to the
    /// Docker daemon" — checamos a conectividade antes para tratar como no-op.
    private func isDaemonRunning() -> Bool {
        shell.execute("docker info", timeout: 15).exitCode == 0
    }

    // MARK: - Parsing

    /// Converte um tamanho do `docker system df` em bytes. Aceita as unidades
    /// decimais que o Docker usa (`B`, `kB`, `MB`, `GB`, `TB`) e descarta o sufixo
    /// de percentual que acompanha o campo `Reclaimable` ("3.913GB (56%)").
    ///
    /// Função pura — o parser anterior removia só o literal "GB" e devolvia `nil`
    /// para "3.913GB (56%)", que é exatamente o formato real do `Reclaimable`.
    /// O resultado era o card do Docker reportar 0 e a limpeza subnotificar tudo.
    static func parseDockerSize(_ raw: String) -> Int64 {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parenthesis = text.firstIndex(of: "(") {
            text = String(text[..<parenthesis]).trimmingCharacters(in: .whitespaces)
        }

        // Ordem importa: "B" é sufixo de todas as outras, então vem por último.
        let units: [(suffix: String, multiplier: Double)] = [
            ("TB", 1_000_000_000_000),
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("KB", 1000),
            ("B", 1)
        ]

        let normalized = text.uppercased()
        for unit in units where normalized.hasSuffix(unit.suffix) {
            let number = normalized.dropLast(unit.suffix.count).trimmingCharacters(in: .whitespaces)
            guard let value = Double(number) else { return 0 }
            return Int64(value * unit.multiplier)
        }

        return 0
    }

    // MARK: - Inventário

    /// Um volume local com o necessário para decidir se é lixo ou dado do usuário.
    private struct VolumeInfo {
        let name: String
        let size: Int64
        let inUse: Bool
        /// Volumes anônimos recebem o label `com.docker.volume.anonymous` do próprio
        /// Docker. É a marca autoritativa: adivinhar pelo nome (64 hex) erraria em
        /// volumes nomeados com hash e em anônimos de versões antigas.
        let isAnonymous: Bool
    }

    /// Lista os volumes locais com tamanho e uso. Uma chamada só — `docker system
    /// df -v` já traz tudo, enquanto `docker volume ls` devolve `Size: N/A`.
    private func localVolumes() -> [VolumeInfo] {
        let result = shell.execute(
            "docker system df -v --format '{{json .Volumes}}'",
            timeout: Self.inspectionTimeout
        )
        guard result.exitCode == 0,
              let data = result.output.data(using: .utf8),
              let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }

        return entries.map { entry in
            let labels = entry["Labels"] as? String ?? ""
            let links = Int(entry["Links"] as? String ?? "0") ?? 0
            return VolumeInfo(
                name: entry["Name"] as? String ?? "",
                size: Self.parseDockerSize(entry["Size"] as? String ?? ""),
                inUse: links > 0,
                isAnonymous: labels.contains("com.docker.volume.anonymous")
            )
        }
    }

    /// Espaço recuperável por tipo ("Images", "Containers", "Local Volumes",
    /// "Build Cache"), em bytes.
    private func reclaimableByType() -> [String: Int64] {
        let result = shell.execute("docker system df --format '{{.Type}}|{{.Reclaimable}}'", timeout: 60)
        guard result.exitCode == 0 else { return [:] }

        var totals: [String: Int64] = [:]
        for line in result.output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "|")
            guard parts.count == 2 else { continue }
            totals[parts[0].trimmingCharacters(in: .whitespaces)] = Self.parseDockerSize(parts[1])
        }
        return totals
    }

    /// Soma o tamanho de todos os tipos. Usado para medir o antes/depois da
    /// limpeza — o código antigo lia só `head -1`, ou seja, apenas as imagens,
    /// e creditava zero ao que o prune de cache e volumes liberava.
    private func totalDockerSize() -> Int64 {
        let result = shell.execute("docker system df --format '{{.Size}}'", timeout: 60)
        guard result.exitCode == 0 else { return 0 }
        return result.output
            .components(separatedBy: "\n")
            .reduce(Int64(0)) { $0 + Self.parseDockerSize($1) }
    }

    /// Redes sem nenhum container anexado, fora as três embutidas (bridge/host/none),
    /// que o Docker nunca remove.
    private func unusedNetworkCount() -> Int {
        let result = shell.execute("docker network ls --filter dangling=true -q | wc -l", timeout: 30)
        return Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    // MARK: - Atualização em staging

    /// O Docker Desktop baixa a próxima versão para
    /// `~/Library/Application Support/com.docker.install/in_progress/Docker.app`
    /// e aplica no próximo restart. Enquanto a cópia ali for MAIS NOVA que a
    /// instalada, é uma atualização pendente e não pode ser tocada. Só quando a
    /// versão em staging já foi instalada (ou é mais antiga) a cópia virou lixo.
    private let stagedInstallerPath = "~/Library/Application Support/com.docker.install/in_progress"
    private let installedAppPath = "/Applications/Docker.app"

    /// `true` quando a cópia em staging não traz nada além do que já está
    /// instalado. Sem versão legível de qualquer um dos lados, preserva.
    static func isStagedInstallerStale(stagedVersion: String?, installedVersion: String?) -> Bool {
        guard let staged = stagedVersion, let installed = installedVersion else { return false }
        func numbers(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let stagedNumbers = numbers(staged)
        let installedNumbers = numbers(installed)
        guard !stagedNumbers.isEmpty, !installedNumbers.isEmpty else { return false }
        return !installedNumbers.lexicographicallyPrecedes(stagedNumbers)
    }

    private func bundleShortVersion(at appPath: String) -> String? {
        let plist = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = FileManager.default.contents(atPath: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    /// Path e tamanho da pasta de staging, se ela existir e já estiver obsoleta.
    private func staleStagedInstaller() -> (path: String, size: Int64)? {
        let stagingDir = fileHelper.expandPath(stagedInstallerPath)
        let stagedApp = (stagingDir as NSString).appendingPathComponent("Docker.app")
        guard fileHelper.fileExists(atPath: stagedApp) else { return nil }
        guard Self.isStagedInstallerStale(
            stagedVersion: bundleShortVersion(at: stagedApp),
            installedVersion: bundleShortVersion(at: installedAppPath)
        ) else {
            logger.log("Docker: atualização pendente em staging; preservada", level: .debug)
            return nil
        }
        return (stagingDir, fileHelper.sizeOfDirectory(atPath: stagingDir))
    }

    /// Move a pasta de staging obsoleta para a Lixeira (remoção direta como fallback).
    private func cleanStaleStagedInstaller(errors: inout [String]) -> (bytes: Int64, removed: Int) {
        guard let staged = staleStagedInstaller() else { return (0, 0) }
        if fileHelper.trashItem(atPath: staged.path) {
            return (staged.size, 1)
        }
        do {
            try fileHelper.removeItem(atPath: staged.path)
            return (staged.size, 1)
        } catch {
            errors.append("Failed to remove stale Docker staged update")
            return (0, 0)
        }
    }

    /// Resultado de uma limpeza que parou antes de falar com o daemon (Docker
    /// ausente ou desligado): só o que foi feito fora da VM conta.
    private func offlineResult(
        startTime: Date, bytesRemoved: Int64, filesRemoved: Int, errors: [String]
    ) -> CleaningResult {
        CleaningResult(
            category: category, bytesRemoved: bytesRemoved, filesRemoved: filesRemoved, errors: errors,
            executionTime: Date().timeIntervalSince(startTime), success: errors.isEmpty
        )
    }

    private func scoutCacheSize() -> Int64 {
        let path = fileHelper.expandPath("~/.docker/scout")
        guard fileHelper.fileExists(atPath: path) else { return 0 }
        return fileHelper.sizeOfDirectory(atPath: path)
    }

    // MARK: - Scan

    private func offlineScan(_ items: [String], size: Int64) -> ScanResult {
        ScanResult(category: category, estimatedSize: size, itemCount: items.count, items: items)
    }

    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var items: [String] = []
        var estimatedSize: Int64 = 0

        // Fora da VM, não depende do daemon: instalador em staging já superado.
        if let staged = staleStagedInstaller(), staged.size > 0 {
            items.append("Stale staged update: \(fileHelper.formatBytes(staged.size))")
            estimatedSize += staged.size
        }

        guard shell.checkCommandExists("docker") else {
            return offlineScan(items + ["Docker not installed"], size: estimatedSize)
        }
        guard isDaemonRunning() else {
            return offlineScan(items + ["Docker not running"], size: estimatedSize)
        }

        progress?("Inspecting Docker...")

        let reclaimable = reclaimableByType()

        // Containers parados. `docker container prune` remove todos os que não
        // estão de pé (created/exited/dead), não só os "exited".
        let stopped = shell.execute("docker ps -aq -f status=exited -f status=created -f status=dead | wc -l")
        if let count = Int(stopped.output.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 {
            items.append("\(count) stopped containers")
            estimatedSize += reclaimable["Containers"] ?? 0
        }

        // Imagens: dangling por padrão, todas as não usadas no modo agressivo.
        let aggressive = CleaningOptions.shared.aggressiveMode
        let imageBytes = reclaimable["Images"] ?? 0
        if aggressive {
            // Com `-a` o ganho é o recuperável inteiro; contar imagens não diz nada.
            if imageBytes > 0 {
                items.append("Unused images: \(fileHelper.formatBytes(imageBytes))")
                estimatedSize += imageBytes
            }
        } else {
            let dangling = shell.execute("docker images -f dangling=true -q | wc -l")
            if let count = Int(dangling.output.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 {
                items.append("\(count) dangling images")
                estimatedSize += imageBytes
            }
        }

        // Build cache — só reporta quando existe de fato. O código antigo usava
        // `grep -i build`, que casa com a linha "Build Cache 0B" e fazia o item
        // aparecer sempre.
        let buildCache = reclaimable["Build Cache"] ?? 0
        if buildCache > 0 {
            items.append("Build cache: \(fileHelper.formatBytes(buildCache))")
            estimatedSize += buildCache
        }

        progress?("Measuring volumes...")
        let volumes = localVolumes()
        let unused = volumes.filter { !$0.inUse }

        // Anônimos não usados são sobras órfãs de containers já removidos: ninguém
        // os criou de propósito, então é seguro remover.
        let anonymous = unused.filter(\.isAnonymous)
        let anonymousBytes = anonymous.reduce(Int64(0)) { $0 + $1.size }
        if !anonymous.isEmpty {
            items.append("\(anonymous.count) unused anonymous volumes: \(fileHelper.formatBytes(anonymousBytes))")
            estimatedSize += anonymousBytes
        }

        // Nomeados NUNCA entram na limpeza automática nem no total estimado: um
        // volume "não usado" é só um volume sem container anexado agora, e um
        // compose parado deixa o banco de dados exatamente nesse estado. Listamos
        // com nome e tamanho para a remoção ser uma decisão consciente.
        let named = unused.filter { !$0.isAnonymous }.sorted { $0.size > $1.size }
        if !named.isEmpty {
            let namedBytes = named.reduce(Int64(0)) { $0 + $1.size }
            items.append("⚠ \(named.count) unused named volumes (\(fileHelper.formatBytes(namedBytes))) " +
                "— kept, may hold data. Remove manually:")
            for volume in named {
                items.append("    docker volume rm \(volume.name)  (\(fileHelper.formatBytes(volume.size)))")
            }
        }

        let networks = unusedNetworkCount()
        if networks > 0 {
            items.append("\(networks) unused networks")
        }

        // Cache do Docker Scout (análise de vulnerabilidades, regenerável).
        let scout = scoutCacheSize()
        if scout > 0 {
            items.append("Docker Scout cache: \(fileHelper.formatBytes(scout))")
            estimatedSize += scout
        }

        logger.log(
            "Docker: \(fileHelper.formatBytes(estimatedSize)) recuperáveis; " +
                "\(named.count) volume(s) nomeado(s) preservado(s)",
            level: .info
        )

        return ScanResult(
            category: category,
            estimatedSize: estimatedSize,
            itemCount: items.count,
            items: items
        )
    }

    // MARK: - Clean

    func clean() async -> CleaningResult {
        let startTime = Date()
        var filesRemoved = 0
        var errors: [String] = []

        // 0. Instalador em staging já superado (fora da VM; não depende do daemon).
        let staged = cleanStaleStagedInstaller(errors: &errors)
        let stagedBytes = staged.bytes
        filesRemoved += staged.removed

        // Docker ausente ou daemon desligado = nada mais a limpar (não é uma falha).
        guard shell.checkCommandExists("docker") else {
            logger.log("Docker não instalado; pulando limpeza.", level: .info)
            return offlineResult(
                startTime: startTime, bytesRemoved: stagedBytes, filesRemoved: filesRemoved, errors: errors
            )
        }
        guard isDaemonRunning() else {
            logger.log("Docker daemon não está rodando; nada a limpar.", level: .info)
            return offlineResult(
                startTime: startTime, bytesRemoved: stagedBytes, filesRemoved: filesRemoved, errors: errors
            )
        }

        let beforeSize = totalDockerSize()

        // 1. Containers parados (sem forçar os que estão de pé).
        let containers = shell.execute("docker container prune -f", timeout: 60)
        if containers.exitCode != 0 {
            errors.append("Failed to clean containers: \(containers.error)")
        } else {
            filesRemoved += containers.output.components(separatedBy: "\n").filter { $0.contains("deleted") }.count
        }

        // 2. Imagens. No modo agressivo, TODAS as não usadas (-a); senão, só as
        //    dangling (sem tag). `-a` recupera muito mais, mas exige repull/rebuild.
        let imagePrune = CleaningOptions.shared.aggressiveMode ? "docker image prune -a -f" : "docker image prune -f"
        let images = shell.execute(imagePrune, timeout: 300)
        if images.exitCode != 0 {
            errors.append("Failed to clean images: \(images.error)")
        } else {
            filesRemoved += images.output.components(separatedBy: "\n").filter { $0.contains("deleted") }.count
        }

        // 3. Todo o build cache (regenerável, sem risco de perda de dados).
        let buildCache = shell.execute("docker builder prune -a -f", timeout: 300)
        if buildCache.exitCode != 0 {
            errors.append("Failed to clean build cache: \(buildCache.error)")
        }

        // 4. Redes sem container anexado. O compose recria a sua no próximo `up`.
        let networks = shell.execute("docker network prune -f", timeout: 60)
        if networks.exitCode != 0 {
            errors.append("Failed to clean networks: \(networks.error)")
        } else {
            filesRemoved += networks.output.components(separatedBy: "\n")
                .filter { !$0.isEmpty && !$0.hasSuffix(":") }.count
        }

        // 5. Volumes: SÓ os anônimos não usados, um a um. Nunca `docker volume
        //    prune`, que varre também os nomeados — um banco de um compose parado
        //    conta como "não usado" e seria apagado junto.
        for volume in localVolumes() where !volume.inUse && volume.isAnonymous {
            let removal = shell.execute("docker volume rm \(volume.name)", timeout: 60)
            if removal.exitCode == 0 {
                filesRemoved += 1
                logger.log("Volume anônimo removido: \(volume.name)", level: .info)
            } else {
                errors.append("Failed to remove volume \(volume.name)")
            }
        }

        let afterSize = totalDockerSize()
        var bytesRemoved = max(0, beforeSize - afterSize) + stagedBytes

        // 6. Cache do Docker Scout (fora da VM; regenerado na próxima análise).
        //    Somado DEPOIS do delta da VM para não ser sobrescrito.
        let scout = cleanScoutCache(errors: &errors)
        bytesRemoved += scout.bytes
        filesRemoved += scout.removed

        // Nota importante: o prune libera espaço DENTRO da VM do Docker, mas o
        // arquivo de disco (Docker.raw, em ~/Library/Containers/com.docker.docker)
        // não encolhe sozinho. Para devolver o espaço ao macOS é preciso usar o
        // "reclaim" do Docker Desktop (Settings > Resources) ou recriar o disco.
        logger.log(
            "Docker: espaço liberado dentro da VM. O Docker.raw não encolhe automaticamente — " +
                "use o reclaim do Docker Desktop se precisar devolver o espaço ao sistema.",
            level: .info
        )

        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: Date().timeIntervalSince(startTime),
            success: errors.isEmpty
        )
    }

    /// Remove ~/.docker/scout (Lixeira primeiro; remoção direta como fallback).
    private func cleanScoutCache(errors: inout [String]) -> (bytes: Int64, removed: Int) {
        let scoutPath = fileHelper.expandPath("~/.docker/scout")
        guard fileHelper.fileExists(atPath: scoutPath) else { return (0, 0) }

        let scoutSize = fileHelper.sizeOfDirectory(atPath: scoutPath)
        if fileHelper.trashItem(atPath: scoutPath) {
            return (scoutSize, 1)
        }
        do {
            try fileHelper.removeItem(atPath: scoutPath)
            return (scoutSize, 1)
        } catch {
            errors.append("Failed to clean Docker Scout cache")
            return (0, 0)
        }
    }
}
