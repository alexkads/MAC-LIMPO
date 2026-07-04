import Foundation

/// Limpa cache de browser (gecko), fileCache e logs do TikTok LIVE Studio.
/// NÃO toca em effects, overlays, imagens, aiassets ou Local Storage — são
/// dados/criações do usuário.
final class TikTokLiveStudioCleaningService: PathBasedCleaningService {
    init() {
        let base = "~/Library/Application Support/TikTok LIVE Studio"
        super.init(category: .tiktokLiveStudio, targets: [
            CleanTarget("\(base)/gecko_cache", label: "Browser cache", strategy: .removeContents),
            CleanTarget("\(base)/fileCache", label: "File cache", strategy: .removeContents),
            CleanTarget("\(base)/logs", label: "Logs", strategy: .removeContents)
        ])
    }
}
