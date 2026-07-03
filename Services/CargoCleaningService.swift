import Foundation

/// Limpa cache de registry, index e git do Cargo/Rust.
final class CargoCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .cargo, targets: [
            CleanTarget("~/.cargo/registry/cache"),
            CleanTarget("~/.cargo/registry/index"),
            CleanTarget("~/.cargo/git")
        ])
    }
}
