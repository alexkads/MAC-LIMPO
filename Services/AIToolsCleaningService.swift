import Foundation

/// Limpa caches de ferramentas de IA (Claude, Antigravity, Trae, Cursor, Copilot,
/// Codeium, Tabnine, Amazon Q). Remove o conteúdo, preservando as pastas.
final class AIToolsCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .aiTools, targets: [
            // Claude
            CleanTarget("~/Library/Application Support/Claude/Cache", label: "Claude Cache", strategy: .removeContents),
            CleanTarget(
                "~/Library/Application Support/Claude/Code Cache",
                label: "Claude Code Cache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Claude/GPUCache",
                label: "Claude GPUCache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Caches/com.anthropic.claudefordesktop",
                label: "Claude cache",
                strategy: .removeContents
            ),
            // Bundles de VM do Claude Desktop (Cowork): ~10 GB re-baixáveis,
            // mas custosos de re-baixar — só no modo agressivo.
            CleanTarget(
                "~/Library/Application Support/Claude/vm_bundles",
                label: "Claude VM bundles",
                strategy: .removeContents,
                aggressive: true
            ),
            // Antigravity (Gemini)
            CleanTarget(
                "~/Library/Application Support/Antigravity/Cache",
                label: "Antigravity Cache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Antigravity/CachedData",
                label: "Antigravity CachedData",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Antigravity/Code Cache",
                label: "Antigravity Code Cache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Antigravity/GPUCache",
                label: "Antigravity GPUCache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Caches/com.google.antigravity",
                label: "Antigravity cache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Caches/antigravity-updater",
                label: "Antigravity updater",
                strategy: .removeContents
            ),
            CleanTarget("~/.gemini/antigravity-backup", label: "Antigravity backup"),
            // Trae
            CleanTarget("~/Library/Application Support/Trae/Cache", label: "Trae Cache", strategy: .removeContents),
            CleanTarget(
                "~/Library/Application Support/Trae/CachedData",
                label: "Trae CachedData",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Trae/CachedExtensionVSIXs",
                label: "Trae Extensions",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Trae/Code Cache",
                label: "Trae Code Cache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Trae/GPUCache",
                label: "Trae GPUCache",
                strategy: .removeContents
            ),
            CleanTarget("~/Library/Application Support/Trae/logs", label: "Trae logs", strategy: .removeContents),
            // Cursor AI
            CleanTarget(
                "~/Library/Application Support/Cursor/CachedData",
                label: "Cursor CachedData",
                strategy: .removeContents
            ),
            CleanTarget("~/Library/Application Support/Cursor/Cache", label: "Cursor Cache", strategy: .removeContents),
            CleanTarget(
                "~/Library/Application Support/Cursor/Code Cache",
                label: "Cursor Code Cache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Application Support/Cursor/GPUCache",
                label: "Cursor GPUCache",
                strategy: .removeContents
            ),
            CleanTarget("~/Library/Application Support/Cursor/logs", label: "Cursor logs", strategy: .removeContents),
            // GitHub Copilot
            CleanTarget("~/Library/Caches/com.github.Copilot", label: "Copilot cache", strategy: .removeContents),
            CleanTarget(
                "~/Library/Application Support/github-copilot",
                label: "Copilot data",
                strategy: .removeContents
            ),
            // Codeium
            CleanTarget("~/Library/Caches/codeium", label: "Codeium cache", strategy: .removeContents),
            CleanTarget("~/Library/Application Support/Codeium", label: "Codeium data", strategy: .removeContents),
            // Tabnine
            CleanTarget("~/.tabnine", label: "Tabnine", strategy: .removeContents),
            CleanTarget("~/Library/Caches/com.tabnine.TabNine", label: "Tabnine cache", strategy: .removeContents),
            // Amazon Q
            CleanTarget("~/Library/Application Support/Amazon Q", label: "Amazon Q", strategy: .removeContents),
            CleanTarget("~/Library/Caches/com.amazon.codewhisperer", label: "Amazon Q cache", strategy: .removeContents)
        ])
    }
}
