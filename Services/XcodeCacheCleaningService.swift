import Foundation

class XcodeCacheCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .xcodeCache
    
    // Caches e dados derivados do Xcode
    private let xcodePaths = [
        // DerivedData - arquivos de build temporários
        "~/Library/Developer/Xcode/DerivedData",
        
        // Archives - builds arquivados (geralmente muito grandes)
        "~/Library/Developer/Xcode/Archives",
        
        // Device Support - símbolos de debug de dispositivos físicos
        "~/Library/Developer/Xcode/iOS DeviceSupport",
        "~/Library/Developer/Xcode/watchOS DeviceSupport",
        "~/Library/Developer/Xcode/tvOS DeviceSupport",
        "~/Library/Developer/Xcode/visionOS DeviceSupport",
        
        // Caches do Xcode
        "~/Library/Caches/com.apple.dt.Xcode",
        
        // Caches do Simulator
        "~/Library/Developer/CoreSimulator/Caches",
        
        // Logs do Xcode
        "~/Library/Developer/Xcode/UserData/IDEEditorInteractivityHistory",
        "~/Library/Developer/Xcode/UserData/IB Support",
        
        // Swift Package Manager caches
        "~/Library/Caches/org.swift.swiftpm",
        "~/Library/org.swift.swiftpm",
        
        // Index e precompiled modules
        "~/Library/Developer/Xcode/UserData/PreviewDevices",
        
        // DocumentRevisions
        "~/Library/Developer/Xcode/UserData/DocumentRevisions-V100",
        
        // Xcode previews temporários
        "~/Library/Developer/Xcode/UserData/Previews",
        
        // Produtos de build antigos
        "~/Library/Developer/Xcode/Products"
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        logger.log("Iniciando escaneamento do ambiente de desenvolvimento Xcode", level: .info)
        progress?("Checking Xcode paths...")
        
        for path in xcodePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let readablePath = getReadableName(for: path)
                progress?("Scanning \(readablePath)...")
                
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    totalSize += size
                    items.append("\(readablePath): \(fileHelper.formatBytes(size))")
                    logger.log("Encontrado: \(readablePath) - \(fileHelper.formatBytes(size))", level: .debug)
                }
            }
        }
        
        // Verificar Simuladores antigos/não utilizados
        let simulatorInfo = await scanOldSimulators()
        if simulatorInfo.size > 0 {
            totalSize += simulatorInfo.size
            items.append(simulatorInfo.description)
        }
        
        logger.log("Escaneamento concluído: \(fileHelper.formatBytes(totalSize)) em \(items.count) categorias", level: .info)
        
        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: items.count,
            items: items
        )
    }
    
    // Mapear caminhos para nomes mais legíveis
    private func getReadableName(for path: String) -> String {
        switch path {
        case let p where p.contains("DerivedData"):
            return "DerivedData (builds temporários)"
        case let p where p.contains("Archives"):
            return "Archives (builds arquivados)"
        case let p where p.contains("iOS DeviceSupport"):
            return "iOS DeviceSupport (símbolos)"
        case let p where p.contains("watchOS DeviceSupport"):
            return "watchOS DeviceSupport (símbolos)"
        case let p where p.contains("tvOS DeviceSupport"):
            return "tvOS DeviceSupport (símbolos)"
        case let p where p.contains("visionOS DeviceSupport"):
            return "visionOS DeviceSupport (símbolos)"
        case let p where p.contains("com.apple.dt.Xcode"):
            return "Caches do Xcode"
        case let p where p.contains("CoreSimulator/Caches"):
            return "Caches do Simulator"
        case let p where p.contains("swiftpm"):
            return "Swift Package Manager"
        case let p where p.contains("Previews"):
            return "Xcode Previews"
        case let p where p.contains("Products"):
            return "Build Products"
        default:
            return (path as NSString).lastPathComponent
        }
    }
    
    // Verificar simuladores antigos que não são mais necessários
    private func scanOldSimulators() async -> (size: Int64, description: String) {
        let simPath = fileHelper.expandPath("~/Library/Developer/CoreSimulator/Devices")
        guard fileHelper.fileExists(atPath: simPath) else {
            return (0, "")
        }
        
        var oldSimsSize: Int64 = 0
        var oldSimsCount = 0
        let contents = fileHelper.contentsOfDirectory(atPath: simPath)
        
        for device in contents {
            let devicePath = (simPath as NSString).appendingPathComponent(device)
            let plistPath = (devicePath as NSString).appendingPathComponent("device.plist")
            
            if fileHelper.fileExists(atPath: plistPath) {
                // Verificar se o simulador não foi usado recentemente
                if let attrs = try? FileManager.default.attributesOfItem(atPath: devicePath),
                   let modDate = attrs[.modificationDate] as? Date {
                    let daysSinceModified = Calendar.current.dateComponents([.day], from: modDate, to: Date()).day ?? 0
                    
                    // Considerar simuladores não usados há mais de 90 dias como "antigos"
                    if daysSinceModified > 90 {
                        oldSimsSize += fileHelper.sizeOfDirectory(atPath: devicePath)
                        oldSimsCount += 1
                    }
                }
            }
        }
        
        if oldSimsCount > 0 {
            return (oldSimsSize, "Simuladores antigos (\(oldSimsCount) dispositivos): \(fileHelper.formatBytes(oldSimsSize))")
        }
        
        return (0, "")
    }
    
    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []
        
        logger.log("Iniciando limpeza do ambiente de desenvolvimento Xcode", level: .info)
        
        // 1. Limpar caches e derived data
        for path in xcodePaths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                let readableName = getReadableName(for: path)
                
                logger.log("Limpando \(readableName)...", level: .info)
                
                let contents = fileHelper.contentsOfDirectory(atPath: expandedPath)
                
                for item in contents {
                    let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                    do {
                        try fileHelper.removeItem(atPath: itemPath)
                        filesRemoved += 1
                        logger.log("Removido: \(item)", level: .debug)
                    } catch {
                        let errorMsg = "Falha ao remover \(item): \(error.localizedDescription)"
                        errors.append(errorMsg)
                        logger.log(errorMsg, level: .error)
                    }
                }
                
                bytesRemoved += size
            }
        }
        
        // 2. Limpar simuladores antigos
        let simResult = await cleanOldSimulators()
        bytesRemoved += simResult.bytesRemoved
        filesRemoved += simResult.filesRemoved
        errors.append(contentsOf: simResult.errors)
        
        // 3. Limpar Swift Package Manager build artifacts em projetos
        let spmResult = await cleanSwiftPMBuildArtifacts()
        bytesRemoved += spmResult.bytesRemoved
        filesRemoved += spmResult.filesRemoved
        errors.append(contentsOf: spmResult.errors)
        
        let executionTime = Date().timeIntervalSince(startTime)
        
        logger.log("Limpeza concluída: \(fileHelper.formatBytes(bytesRemoved)) removidos, \(filesRemoved) arquivos", level: .info)
        
        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: executionTime,
            success: errors.count < filesRemoved / 2
        )
    }
    
    // Limpar simuladores antigos (não usados há mais de 90 dias)
    private func cleanOldSimulators() async -> (bytesRemoved: Int64, filesRemoved: Int, errors: [String]) {
        let simPath = fileHelper.expandPath("~/Library/Developer/CoreSimulator/Devices")
        guard fileHelper.fileExists(atPath: simPath) else {
            return (0, 0, [])
        }
        
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []
        
        logger.log("Verificando simuladores antigos...", level: .info)
        
        let contents = fileHelper.contentsOfDirectory(atPath: simPath)
        
        for device in contents {
            let devicePath = (simPath as NSString).appendingPathComponent(device)
            let plistPath = (devicePath as NSString).appendingPathComponent("device.plist")
            
            if fileHelper.fileExists(atPath: plistPath) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: devicePath),
                   let modDate = attrs[.modificationDate] as? Date {
                    let daysSinceModified = Calendar.current.dateComponents([.day], from: modDate, to: Date()).day ?? 0
                    
                    // Remover simuladores não usados há mais de 90 dias
                    if daysSinceModified > 90 {
                        let size = fileHelper.sizeOfDirectory(atPath: devicePath)
                        do {
                            try fileHelper.removeItem(atPath: devicePath)
                            bytesRemoved += size
                            filesRemoved += 1
                            logger.log("Simulador antigo removido: \(device)", level: .debug)
                        } catch {
                            let errorMsg = "Falha ao remover simulador \(device): \(error.localizedDescription)"
                            errors.append(errorMsg)
                            logger.log(errorMsg, level: .error)
                        }
                    }
                }
            }
        }
        
        if filesRemoved > 0 {
            logger.log("Removidos \(filesRemoved) simuladores antigos", level: .info)
        }
        
        return (bytesRemoved, filesRemoved, errors)
    }
    
    // Limpar build artifacts do Swift Package Manager em diretórios de projetos
    private func cleanSwiftPMBuildArtifacts() async -> (bytesRemoved: Int64, filesRemoved: Int, errors: [String]) {
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []
        
        // Procurar por diretórios .build em locais comuns
        let searchPaths = [
            fileHelper.expandPath("~/Developer"),
            fileHelper.expandPath("~/Projects"),
            fileHelper.expandPath("~/Documents")
        ]
        
        logger.log("Procurando por artifacts de build do Swift PM...", level: .info)
        
        for searchPath in searchPaths {
            guard fileHelper.fileExists(atPath: searchPath) else { continue }
            
            // Usar find para localizar diretórios .build
            let findCommand = "find '\(searchPath)' -type d -name '.build' -maxdepth 5 2>/dev/null"
            if let result = ShellExecutor.shared.execute(findCommand),
               !result.output.isEmpty {
                let buildDirs = result.output.components(separatedBy: "\n").filter { !$0.isEmpty }
                
                for buildDir in buildDirs {
                    let size = fileHelper.sizeOfDirectory(atPath: buildDir)
                    do {
                        try fileHelper.removeItem(atPath: buildDir)
                        bytesRemoved += size
                        filesRemoved += 1
                        logger.log("Removido diretório .build: \(buildDir)", level: .debug)
                    } catch {
                        let errorMsg = "Falha ao remover \(buildDir): \(error.localizedDescription)"
                        errors.append(errorMsg)
                        logger.log(errorMsg, level: .error)
                    }
                }
            }
        }
        
        if filesRemoved > 0 {
            logger.log("Removidos \(filesRemoved) diretórios .build do Swift PM", level: .info)
        }
        
        return (bytesRemoved, filesRemoved, errors)
    }
}
