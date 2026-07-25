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
            CleanTarget("~/Library/Application Support/Google/GoogleUpdater", label: "Google Updater (old versions)")
        ])
    }
}
