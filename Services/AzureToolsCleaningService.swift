import Foundation

/// Remove os binários do Azure Functions Core Tools baixados pelo plugin Azure
/// do IntelliJ. Versões antigas acumulam gigabytes; o plugin re-baixa a versão
/// atual na próxima vez que for necessária.
final class AzureToolsCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .azureTools, targets: [
            CleanTarget(
                "~/.AzureToolsForIntelliJ/AzureFunctionsCoreTools",
                label: "Azure Functions Core Tools",
                strategy: .removeContents
            )
        ])
    }
}
