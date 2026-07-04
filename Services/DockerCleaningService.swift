import Foundation

class DockerCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .docker

    func scan(progress _: ((String) -> Void)?) async -> ScanResult {
        var estimatedSize: Int64 = 0
        var items: [String] = []

        // Verifica se Docker está instalado
        guard shell.checkCommandExists("docker") else {
            return ScanResult(category: category, estimatedSize: 0, itemCount: 0, items: ["Docker not installed"])
        }

        // Conta containers parados
        let containersResult = shell.execute("docker ps -aq -f status=exited | wc -l")
        if let count = Int(containersResult.output.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 {
            items.append("\(count) stopped containers")
        }

        // Conta imagens não utilizadas
        let imagesResult = shell.execute("docker images -f dangling=true -q | wc -l")
        if let count = Int(imagesResult.output.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 {
            items.append("\(count) dangling images")
        }

        // Conta build cache (limpeza superficial não remove volumes)
        let buildCacheResult = shell.execute("docker system df --format '{{.Type}},{{.Reclaimable}}' | grep -i build")
        if !buildCacheResult.output.isEmpty {
            items.append("Build cache")
        }

        // Estima tamanho do build cache
        let sizeResult = shell.execute("docker system df --format '{{.Reclaimable}}' | head -1")
        let sizeStr = sizeResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Converte tamanho (formato: "1.5GB" ou "500MB")
        if sizeStr.contains("GB") {
            if let value = Double(sizeStr.replacingOccurrences(of: "GB", with: "")) {
                estimatedSize = Int64(value * 1_000_000_000)
            }
        } else if sizeStr.contains("MB") {
            if let value = Double(sizeStr.replacingOccurrences(of: "MB", with: "")) {
                estimatedSize = Int64(value * 1_000_000)
            }
        }

        return ScanResult(
            category: category,
            estimatedSize: estimatedSize,
            itemCount: items.count,
            items: items
        )
    }

    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []

        guard shell.checkCommandExists("docker") else {
            return CleaningResult(
                category: category,
                errors: ["Docker not installed"],
                success: false
            )
        }

        // Obtém tamanho antes da limpeza
        let beforeResult = shell.execute("docker system df --format '{{.Size}}' | head -1")
        let beforeSize = parseDiskSize(beforeResult.output)

        // Limpeza superficial e segura do Docker:
        // 1. Remove apenas containers parados (sem forçar)
        let containersResult = shell.execute("docker container prune -f", timeout: 60)
        if containersResult.exitCode != 0 {
            errors.append("Failed to clean containers: \(containersResult.error)")
        } else {
            let lines = containersResult.output.components(separatedBy: "\n")
            filesRemoved += lines.filter { $0.contains("deleted") }.count
        }

        // 2. Remove imagens. No modo agressivo, TODAS as não usadas (-a); senão,
        //    só as dangling (sem tag). `-a` recupera muito mais, mas exige repull/rebuild.
        let imagePruneCmd = CleaningOptions.shared.aggressiveMode
            ? "docker image prune -a -f"
            : "docker image prune -f"
        let imagesResult = shell.execute(imagePruneCmd, timeout: 120)
        if imagesResult.exitCode != 0 {
            errors.append("Failed to clean images: \(imagesResult.error)")
        } else {
            let lines = imagesResult.output.components(separatedBy: "\n")
            filesRemoved += lines.filter { $0.contains("deleted") }.count
        }

        // 3. Remove TODO o build cache (regenerável). `-a` recupera bem mais que
        //    só o dangling, sem risco de perda de dados (volumes/redes intactos).
        let cacheResult = shell.execute("docker builder prune -a -f", timeout: 120)
        if cacheResult.exitCode != 0 {
            errors.append("Failed to clean build cache: \(cacheResult.error)")
        }

        // Obtém tamanho depois da limpeza
        let afterResult = shell.execute("docker system df --format '{{.Size}}' | head -1")
        let afterSize = parseDiskSize(afterResult.output)

        bytesRemoved = max(0, beforeSize - afterSize)

        // Nota importante: o prune libera espaço DENTRO da VM do Docker, mas o
        // arquivo de disco (Docker.raw, em ~/Library/Containers/com.docker.docker)
        // não encolhe sozinho. Para devolver o espaço ao macOS é preciso usar o
        // "reclaim" do Docker Desktop (Settings > Resources) ou recriar o disco.
        // Volumes NÃO são removidos de propósito (podem conter dados do usuário).
        logger.log(
            "Docker: espaço liberado dentro da VM. O Docker.raw não encolhe automaticamente — " +
                "use o reclaim do Docker Desktop se precisar devolver o espaço ao sistema.",
            level: .info
        )

        let executionTime = Date().timeIntervalSince(startTime)

        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: executionTime,
            success: errors.isEmpty
        )
    }

    private func parseDiskSize(_ sizeString: String) -> Int64 {
        let cleaned = sizeString.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.contains("GB") {
            if let value = Double(cleaned.replacingOccurrences(of: "GB", with: "")
                .trimmingCharacters(in: .whitespaces))
            {
                return Int64(value * 1_000_000_000)
            }
        } else if cleaned.contains("MB") {
            if let value = Double(cleaned.replacingOccurrences(of: "MB", with: "")
                .trimmingCharacters(in: .whitespaces))
            {
                return Int64(value * 1_000_000)
            }
        } else if cleaned.contains("KB") {
            if let value = Double(cleaned.replacingOccurrences(of: "KB", with: "")
                .trimmingCharacters(in: .whitespaces))
            {
                return Int64(value * 1000)
            }
        }

        return 0
    }
}
