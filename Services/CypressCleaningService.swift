import Foundation

/// Limpa dados de teste do Cypress (preservando as pastas) e o cache do binário.
final class CypressCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .cypress, targets: [
            CleanTarget("~/Library/Application Support/Cypress/cy", strategy: .removeContents),
            CleanTarget("~/Library/Application Support/Cypress/Partitions", strategy: .removeContents),
            CleanTarget("~/Library/Application Support/Cypress/DawnCache", strategy: .removeContents),
            CleanTarget("~/Library/Application Support/Cypress/GPUCache", strategy: .removeContents),
            CleanTarget("~/Library/Application Support/Cypress/Code Cache", strategy: .removeContents),
            CleanTarget("~/.cache/Cypress", label: "Cypress binary cache")
        ])
    }
}
