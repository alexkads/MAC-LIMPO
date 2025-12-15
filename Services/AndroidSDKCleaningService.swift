import Foundation

class AndroidSDKCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .androidSDK
    
    // Caminhos do Android SDK que podem ser limpos com segurança
    private let androidPaths = [
        // Emuladores antigos - podem ser recriados
        "~/Library/Android/sdk/system-images",
        
        // Cache do Gradle (builds Android)
        "~/.gradle/caches",
        "~/.gradle/daemon",
        "~/.gradle/wrapper/dists",
        
        // Android build cache
        "~/.android/build-cache",
        "~/.android/cache",
        
        // AVD (Android Virtual Device) - emuladores
        "~/.android/avd"
    ]
    
    // Caminhos que NÃO devemos limpar (essenciais)
    // ~/Library/Android/sdk/platform-tools (adb, fastboot)
    // ~/Library/Android/sdk/build-tools (compilação)
    // ~/Library/Android/sdk/platforms (SDKs)
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        logger.log("Iniciando escaneamento do Android SDK", level: .info)
        
        // System Images (emuladores)
        let systemImagesPath = fileHelper.expandPath("~/Library/Android/sdk/system-images")
        if fileHelper.fileExists(atPath: systemImagesPath) {
            let size = fileHelper.sizeOfDirectory(atPath: systemImagesPath)
            if size > 0 {
                totalSize += size
                // Contar imagens disponíveis
                let images = countSystemImages(at: systemImagesPath)
                items.append("System Images (\(images) imagens): \(fileHelper.formatBytes(size))")
                logger.log("System Images: \(fileHelper.formatBytes(size)) - \(images) imagens", level: .debug)
            }
        }
        
        // AVDs (emuladores criados)
        let avdPath = fileHelper.expandPath("~/.android/avd")
        if fileHelper.fileExists(atPath: avdPath) {
            let size = fileHelper.sizeOfDirectory(atPath: avdPath)
            if size > 0 {
                totalSize += size
                let avdCount = countAVDs(at: avdPath)
                items.append("AVDs (\(avdCount) emuladores): \(fileHelper.formatBytes(size))")
                logger.log("AVDs: \(fileHelper.formatBytes(size)) - \(avdCount) emuladores", level: .debug)
            }
        }
        
        // Gradle caches
        var gradleSize: Int64 = 0
        let gradlePaths = ["~/.gradle/caches", "~/.gradle/daemon", "~/.gradle/wrapper/dists"]
        for path in gradlePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                gradleSize += fileHelper.sizeOfDirectory(atPath: expandedPath)
            }
        }
        if gradleSize > 0 {
            totalSize += gradleSize
            items.append("Gradle Cache: \(fileHelper.formatBytes(gradleSize))")
            logger.log("Gradle Cache: \(fileHelper.formatBytes(gradleSize))", level: .debug)
        }
        
        // Android build cache
        var androidCacheSize: Int64 = 0
        let androidCachePaths = ["~/.android/build-cache", "~/.android/cache"]
        for path in androidCachePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                androidCacheSize += fileHelper.sizeOfDirectory(atPath: expandedPath)
            }
        }
        if androidCacheSize > 0 {
            totalSize += androidCacheSize
            items.append("Android Build Cache: \(fileHelper.formatBytes(androidCacheSize))")
            logger.log("Android Build Cache: \(fileHelper.formatBytes(androidCacheSize))", level: .debug)
        }
        
        logger.log("Escaneamento Android SDK concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        
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
        
        logger.log("Iniciando limpeza do Android SDK (modo conservador)", level: .info)
        let startTime = Date()
        
        // IMPORTANTE: Não vamos limpar system-images e AVDs automaticamente
        // pois o usuário pode precisar deles. Apenas caches.
        
        // Limpar Gradle caches (seguros de limpar, serão recriados)
        let gradlePaths = ["~/.gradle/caches", "~/.gradle/daemon"]
        for path in gradlePaths {
            let expandedPath = self.fileHelper.expandPath(path)
            if self.fileHelper.fileExists(atPath: expandedPath) {
                let size = self.fileHelper.sizeOfDirectory(atPath: expandedPath)
                do {
                    try self.fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                    logger.log("Removido Gradle: \(path) (\(self.fileHelper.formatBytes(size)))", level: .debug)
                } catch {
                    errors.append("Falha ao limpar: \(path)")
                }
            }
        }
        
        // Limpar Android build cache
        let androidCachePaths = ["~/.android/build-cache", "~/.android/cache"]
        for path in androidCachePaths {
            let expandedPath = self.fileHelper.expandPath(path)
            if self.fileHelper.fileExists(atPath: expandedPath) {
                let size = self.fileHelper.sizeOfDirectory(atPath: expandedPath)
                do {
                    try self.fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                    logger.log("Removido Android cache: \(path) (\(self.fileHelper.formatBytes(size)))", level: .debug)
                } catch {
                    // Ignorar
                }
            }
        }
        
        // Limpar wrapper/dists antigos do Gradle (versões antigas)
        await self.cleanOldGradleDistributions(bytesRemoved: &bytesRemoved, filesRemoved: &filesRemoved, errors: &errors)
        
        let executionTime = Date().timeIntervalSince(startTime)
        logger.log("Limpeza Android SDK concluída: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)
        
        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: executionTime,
            success: errors.isEmpty
        )
    }
    
    private func countSystemImages(at path: String) -> Int {
        var count = 0
        let contents = fileHelper.contentsOfDirectory(atPath: path)
        for dir in contents {
            let subPath = (path as NSString).appendingPathComponent(dir)
            let subContents = fileHelper.contentsOfDirectory(atPath: subPath)
            count += subContents.count
        }
        return count
    }
    
    private func countAVDs(at path: String) -> Int {
        let contents = fileHelper.contentsOfDirectory(atPath: path)
        return contents.filter { $0.hasSuffix(".avd") }.count
    }
    
    private func cleanOldGradleDistributions(bytesRemoved: inout Int64, filesRemoved: inout Int, errors: inout [String]) async {
        let distsPath = fileHelper.expandPath("~/.gradle/wrapper/dists")
        guard fileHelper.fileExists(atPath: distsPath) else { return }
        
        let contents = fileHelper.contentsOfDirectory(atPath: distsPath)
        var versions: [(name: String, path: String, modDate: Date)] = []
        
        for dir in contents {
            let fullPath = (distsPath as NSString).appendingPathComponent(dir)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
               let modDate = attrs[.modificationDate] as? Date {
                versions.append((dir, fullPath, modDate))
            }
        }
        
        // Ordenar por data e manter apenas as 2 versões mais recentes
        let sorted = versions.sorted { $0.modDate > $1.modDate }
        if sorted.count > 2 {
            for i in 2..<sorted.count {
                let version = sorted[i]
                let size = fileHelper.sizeOfDirectory(atPath: version.path)
                do {
                    try fileHelper.removeItem(atPath: version.path)
                    bytesRemoved += size
                    filesRemoved += 1
                    logger.log("Removido Gradle dist antigo: \(version.name) (\(fileHelper.formatBytes(size)))", level: .debug)
                } catch {
                    // Ignorar
                }
            }
        }
    }
}
