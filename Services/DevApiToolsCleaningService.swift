import Foundation

/// Limpa caches de clientes REST (Postman, Insomnia, Bruno, Hoppscotch, Paw).
/// Pastas "Partitions" (cache do Electron) têm só o conteúdo removido.
final class DevApiToolsCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .devApiTools, targets: [
            // Postman
            CleanTarget(
                "~/Library/Application Support/Postman/Partitions",
                label: "Postman Partitions",
                strategy: .removeContents
            ),
            CleanTarget("~/Library/Application Support/Postman/logs", label: "Postman logs"),
            CleanTarget("~/Library/Application Support/Postman/Code Cache", label: "Postman Code Cache"),
            CleanTarget("~/Library/Application Support/Postman/GPUCache", label: "Postman GPUCache"),
            CleanTarget("~/Library/Application Support/Postman/DawnCache", label: "Postman DawnCache"),
            CleanTarget("~/Library/Caches/com.postmanlabs.mac", label: "Postman cache"),
            // Insomnia
            CleanTarget("~/Library/Application Support/Insomnia/Cache", label: "Insomnia Cache"),
            CleanTarget("~/Library/Application Support/Insomnia/Code Cache", label: "Insomnia Code Cache"),
            CleanTarget("~/Library/Application Support/Insomnia/GPUCache", label: "Insomnia GPUCache"),
            CleanTarget(
                "~/Library/Application Support/Insomnia/Partitions",
                label: "Insomnia Partitions",
                strategy: .removeContents
            ),
            CleanTarget("~/Library/Caches/com.insomnia.app", label: "Insomnia cache"),
            // Bruno
            CleanTarget("~/Library/Application Support/Bruno/Cache", label: "Bruno Cache"),
            CleanTarget("~/Library/Application Support/Bruno/Code Cache", label: "Bruno Code Cache"),
            CleanTarget("~/Library/Application Support/Bruno/GPUCache", label: "Bruno GPUCache"),
            CleanTarget("~/Library/Caches/com.usebruno.app", label: "Bruno cache"),
            // Hoppscotch
            CleanTarget("~/Library/Application Support/Hoppscotch/Cache", label: "Hoppscotch Cache"),
            CleanTarget("~/Library/Application Support/Hoppscotch/Code Cache", label: "Hoppscotch Code Cache"),
            CleanTarget("~/Library/Application Support/Hoppscotch/GPUCache", label: "Hoppscotch GPUCache"),
            // RapidAPI (Paw)
            CleanTarget("~/Library/Caches/com.luckymarmot.Paw", label: "Paw cache"),
            CleanTarget("~/Library/Caches/com.paw.Paw", label: "Paw cache")
        ])
    }
}
