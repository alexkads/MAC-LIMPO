import Foundation

/// Remove modelos de IA locais e caches associados. Modelos baixados pelo
/// usuário (Ollama, LM Studio) são grandes e custosos de re-baixar, então só
/// entram no modo agressivo; caches regeneráveis (Hugging Face, U²-Net) são
/// limpos sempre.
final class AIModelsCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .aiModels, targets: [
            CleanTarget("~/.ollama/models", label: "Ollama models", strategy: .removeContents, aggressive: true),
            CleanTarget("~/.lmstudio/models", label: "LM Studio models", strategy: .removeContents, aggressive: true),
            CleanTarget(
                "~/.lmstudio/extensions",
                label: "LM Studio runtimes",
                strategy: .removeContents,
                aggressive: true
            ),
            CleanTarget("~/.cache/huggingface/hub", label: "Hugging Face cache", strategy: .removeContents),
            CleanTarget("~/.u2net", label: "U²-Net models", strategy: .removeContents)
        ])
    }
}
