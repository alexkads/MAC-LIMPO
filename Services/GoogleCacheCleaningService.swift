import Foundation

/// Limpa caches regeneráveis do perfil do Chrome (Service Worker CacheStorage,
/// Code Cache, GPU caches) e versões antigas do Google Updater. Não toca em
/// histórico, senhas, extensões ou favoritos — só dados recriados pelo uso.
final class GoogleCacheCleaningService: PathBasedCleaningService {
    init() {
        let base = "~/Library/Application Support/Google/Chrome/Default"
        super.init(category: .googleCache, targets: [
            CleanTarget("\(base)/Service Worker/CacheStorage", label: "Chrome service worker cache"),
            CleanTarget("\(base)/Service Worker/ScriptCache", label: "Chrome script cache"),
            CleanTarget("\(base)/Code Cache", label: "Chrome code cache"),
            CleanTarget("\(base)/GPUCache", label: "Chrome GPU cache"),
            CleanTarget("\(base)/DawnWebGPUCache", label: "Chrome WebGPU cache"),
            CleanTarget("\(base)/DawnGraphiteCache", label: "Chrome graphite cache"),
            CleanTarget("~/Library/Application Support/Google/GoogleUpdater", label: "Google Updater (old versions)"),
            // Componentes re-baixados pelo próprio Chrome quando necessários.
            CleanTarget(
                "~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel",
                label: "Chrome on-device AI model",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Google/Chrome/component_crx_cache",
                label: "Chrome component cache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Google/Chrome/screen_ai",
                label: "Chrome Screen AI",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Google/Chrome/optimization_guide_model_store",
                label: "Chrome optimization models",
                strategy: .removeContents
            )
        ])
    }
}
