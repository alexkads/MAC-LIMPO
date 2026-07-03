import Foundation

/// Remove caches regeneráveis do Notion (asset, GPU, code). Preserva as pastas.
final class NotionCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .notionCache, targets: [
            CleanTarget(
                "~/Library/Application Support/Notion/notionAssetCache-v2",
                label: "Notion Asset cache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Notion/DawnCache",
                label: "Notion GPU/Dawn cache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Notion/GPUCache",
                label: "Notion GPU cache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Notion/Code Code",
                label: "Notion Code cache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Notion/Cache",
                label: "Notion General cache",
                strategy: .removeContents
            ),
            CleanTarget("~/Library/Caches/com.notion.id", strategy: .removeContents)
        ])
    }
}
