import Foundation

class MessagingAppsCleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .messagingApps
    
    // Caches e dados temporários de apps de mensagens
    private let messagingPaths: [(app: String, paths: [String])] = [
        ("WhatsApp", [
            "~/Library/Containers/com.whatsapp.WhatsApp/Data/Library/Caches",
            "~/Library/Containers/desktop.WhatsApp/Data/Library/Caches",
            "~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Library/Caches",
            "~/Library/Group Containers/group.com.whatsapp.family/Library/Caches"
        ]),
        ("Microsoft Teams", [
            "~/Library/Containers/com.microsoft.teams2/Data/Library/Caches",
            "~/Library/Application Support/Microsoft/Teams/Cache",
            "~/Library/Application Support/Microsoft/Teams/GPUCache",
            "~/Library/Application Support/Microsoft/Teams/Code Cache",
            "~/Library/Application Support/Microsoft/Teams/Service Worker/CacheStorage"
        ]),
        ("Slack", [
            "~/Library/Application Support/Slack/Cache",
            "~/Library/Application Support/Slack/Code Cache",
            "~/Library/Application Support/Slack/GPUCache",
            "~/Library/Application Support/Slack/Service Worker",
            "~/Library/Caches/com.tinyspeck.slackmacgap"
        ]),
        ("Discord", [
            "~/Library/Application Support/discord/Cache",
            "~/Library/Application Support/discord/Code Cache",
            "~/Library/Application Support/discord/GPUCache",
            "~/Library/Caches/com.hnc.Discord"
        ]),
        ("Telegram", [
            "~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/Library/Caches",
            "~/Library/Caches/ru.keepcoder.Telegram"
        ]),
        ("Zoom", [
            "~/Library/Application Support/zoom.us/data/ZoomAudioDevice",
            "~/Library/Application Support/zoom.us/AutoUpdater",
            "~/Library/Caches/us.zoom.xos",
            "~/Library/Logs/zoom.us"
        ])
    ]
    
    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []
        
        logger.log("Iniciando escaneamento de apps de mensagens", level: .info)
        
        for (app, paths) in messagingPaths {
            var appSize: Int64 = 0
            
            for path in paths {
                let expandedPath = fileHelper.expandPath(path)
                if fileHelper.fileExists(atPath: expandedPath) {
                    appSize += fileHelper.sizeOfDirectory(atPath: expandedPath)
                }
            }
            
            if appSize > 0 {
                totalSize += appSize
                items.append("\(app): \(fileHelper.formatBytes(appSize))")
                logger.log("\(app): \(fileHelper.formatBytes(appSize))", level: .debug)
            }
        }
        
        // Verificar mídia antiga do WhatsApp (opcional - pode ser muito grande)
        let whatsappMediaSize = await scanWhatsAppMedia()
        if whatsappMediaSize > 0 {
            // Não adicionar ao total pois é conteúdo do usuário
            items.append("WhatsApp Mídia (arquivos antigos): \(fileHelper.formatBytes(whatsappMediaSize)) ⚠️")
            logger.log("WhatsApp Mídia antiga: \(fileHelper.formatBytes(whatsappMediaSize))", level: .info)
        }
        
        logger.log("Escaneamento de apps de mensagens concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        
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
        
        logger.log("Iniciando limpeza de caches de apps de mensagens", level: .info)
        let startTime = Date()
        
        for (app, paths) in self.messagingPaths {
            for path in paths {
                let expandedPath = self.fileHelper.expandPath(path)
                if self.fileHelper.fileExists(atPath: expandedPath) {
                    // Limpar conteúdo do diretório, não o diretório em si
                    let contents = self.fileHelper.contentsOfDirectory(atPath: expandedPath)
                    var pathFreed: Int64 = 0
                    
                    for item in contents {
                        let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                        let itemSize = self.fileHelper.sizeOfDirectory(atPath: itemPath)
                        do {
                            try self.fileHelper.removeItem(atPath: itemPath)
                            pathFreed += itemSize
                            filesRemoved += 1
                        } catch {
                            // Ignorar erros individuais
                        }
                    }
                    
                    if pathFreed > 0 {
                        bytesRemoved += pathFreed
                        logger.log("Limpou \(app): \(self.fileHelper.formatBytes(pathFreed))", level: .debug)
                    }
                }
            }
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        logger.log("Limpeza de apps de mensagens concluída: \(fileHelper.formatBytes(bytesRemoved)) liberados", level: .info)
        
        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: executionTime,
            success: errors.isEmpty
        )
    }
    
    // Escanear mídia antiga do WhatsApp (downloads antigos)
    private func scanWhatsAppMedia() async -> Int64 {
        let mediaPaths = [
            "~/Library/Containers/desktop.WhatsApp/Data/Library/Application Support/WhatsApp/Media",
            "~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media"
        ]
        
        var oldMediaSize: Int64 = 0
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        
        for mediaPath in mediaPaths {
            let expandedPath = fileHelper.expandPath(mediaPath)
            guard fileHelper.fileExists(atPath: expandedPath) else { continue }
            
            if let enumerator = FileManager.default.enumerator(atPath: expandedPath) {
                while let file = enumerator.nextObject() as? String {
                    let filePath = (expandedPath as NSString).appendingPathComponent(file)
                    
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
                       let modDate = attrs[.modificationDate] as? Date,
                       modDate < cutoffDate,
                       let size = attrs[.size] as? Int64 {
                        oldMediaSize += size
                    }
                }
            }
        }
        
        return oldMediaSize
    }
}
