import Foundation

/// Limpa os downloads regeneráveis do Zed em Application Support: runtimes Node
/// empacotados, language servers, binário do Copilot, agentes externos e
/// Prettier. O Zed re-baixa o que precisar na próxima abertura.
final class ZedCleaningService: PathBasedCleaningService {
    init() {
        let base = "~/Library/Application Support/Zed"
        super.init(category: .zedCache, targets: [
            CleanTarget("\(base)/node", label: "Zed Node runtimes", strategy: .removeContents),
            CleanTarget("\(base)/languages", label: "Zed language servers", strategy: .removeContents),
            CleanTarget("\(base)/copilot", label: "Zed Copilot", strategy: .removeContents),
            CleanTarget("\(base)/external_agents", label: "Zed external agents", strategy: .removeContents),
            CleanTarget("\(base)/prettier", label: "Zed Prettier", strategy: .removeContents),
            CleanTarget("~/Library/Logs/Zed", label: "Zed logs", strategy: .removeContents)
        ])
    }
}
