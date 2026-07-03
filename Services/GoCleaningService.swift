import Foundation

/// Limpa module cache, build cache e gopls do Go.
final class GoCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .goCache, targets: [
            CleanTarget("~/go/pkg/mod/cache", label: "Go module cache"),
            CleanTarget("~/Library/Caches/go-build", label: "Go build cache"),
            CleanTarget("~/Library/Caches/gopls", label: "gopls language server")
        ])
    }
}
