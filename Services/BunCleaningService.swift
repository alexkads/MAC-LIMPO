import Foundation

/// Limpa o cache global de instalação do Bun. É recriado quando os pacotes são
/// baixados de novo em `bun install`.
final class BunCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .bunCache, targets: [
            CleanTarget("~/.bun/install/cache", label: "Bun install cache")
        ])
    }
}
