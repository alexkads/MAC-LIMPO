import Foundation

/// Limpa os pacotes baixados do pub (Dart/Flutter). São re-obtidos com
/// `flutter pub get` / `dart pub get`. Preserva `~/.pub-cache/bin` e pacotes
/// ativados globalmente, limpando apenas os caches de download.
final class PubCacheCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .pubCache, targets: [
            CleanTarget("~/.pub-cache/hosted", label: "pub hosted packages"),
            CleanTarget("~/.pub-cache/git", label: "pub git packages"),
            CleanTarget("~/.pub-cache/.cache", label: "pub metadata cache")
        ])
    }
}
