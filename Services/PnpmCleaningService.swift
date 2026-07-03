import Foundation

/// Limpa o store global e caches (dlx/metadata) do pnpm.
final class PnpmCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .pnpm, targets: [
            CleanTarget("~/Library/Caches/pnpm/dlx", label: "pnpm cache (dlx)"),
            CleanTarget("~/Library/Caches/pnpm/metadata-full-v1.3", label: "pnpm metadata"),
            CleanTarget("~/Library/Caches/pnpm/metadata-v1.3", label: "pnpm metadata"),
            CleanTarget("~/Library/Caches/pnpm", label: "pnpm cache"),
            CleanTarget("~/Library/pnpm/store", label: "pnpm store (packages)")
        ])
    }
}
