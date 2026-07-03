import Foundation

/// Limpa o cache de downloads do Homebrew.
final class HomebrewCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .homebrew, targets: [
            CleanTarget("~/Library/Caches/Homebrew", label: "Homebrew cache")
        ])
    }
}
