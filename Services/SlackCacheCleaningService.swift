import Foundation

/// Limpa cache e arquivos temporários do Slack.
final class SlackCacheCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .slackCache, targets: [
            CleanTarget("~/Library/Application Support/Slack/Cache"),
            CleanTarget("~/Library/Application Support/Slack/Code Cache"),
            CleanTarget("~/Library/Application Support/Slack/Service Worker/CacheStorage"),
            CleanTarget("~/Library/Application Support/Slack/Local Storage"),
            CleanTarget("~/Library/Caches/com.tinyspeck.slackmacgap"),
            CleanTarget("~/Library/Caches/com.tinyspeck.slackmacgap.ShipIt")
        ])
    }
}
