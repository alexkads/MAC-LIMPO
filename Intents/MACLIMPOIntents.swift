import AppIntents
import Foundation

/// Read-only storage scan exposed to Siri, Shortcuts and Apple Intelligence.
struct ScanStorageIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Mac Storage"
    static let description = IntentDescription(
        "Scans MAC-LIMPO cleaning categories and reports reclaimable space."
    )

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let services = CleaningServiceRegistry.shared.services
        let results = await withTaskGroup(of: ScanResult.self, returning: [ScanResult].self) { group in
            for service in services.values {
                group.addTask { await service.scan(progress: nil) }
            }

            var results: [ScanResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let total = results.reduce(Int64.zero) { $0 + $1.estimatedSize }
        let message = "MAC-LIMPO found \(FileSystemHelper.shared.formatBytes(total)) of potentially reclaimable space across \(results.filter { $0.estimatedSize > 0 }.count) categories."
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

/// Destructive action exposed through the standard App Intents confirmation flow.
struct CleanAllStorageIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Mac Storage"
    static let description = IntentDescription(
        "Moves eligible MAC-LIMPO items to the Trash after confirmation."
    )

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try await requestConfirmation(
            actionName: .continue,
            dialog: IntentDialog("This will move eligible cleaning targets to the Trash. Continue?")
        )

        let services = CleaningServiceRegistry.shared.services
        let results = await withTaskGroup(of: CleaningResult.self, returning: [CleaningResult].self) { group in
            for service in services.values {
                group.addTask { await service.clean() }
            }

            var results: [CleaningResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let bytes = results.reduce(Int64.zero) { $0 + $1.bytesRemoved }
        let files = results.reduce(0) { $0 + $1.filesRemoved }
        let message = "MAC-LIMPO moved \(FileSystemHelper.shared.formatBytes(bytes)) to the Trash from \(files) items."
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct MACLIMPOShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
                intent: ScanStorageIntent(),
                phrases: [
                    "Scan storage with \(.applicationName)",
                    "How much space can \(.applicationName) reclaim"
                ],
                shortTitle: "Scan storage",
                systemImageName: "magnifyingglass"
        )
        AppShortcut(
                intent: CleanAllStorageIntent(),
                phrases: ["Clean storage with \(.applicationName)"],
                shortTitle: "Clean storage",
                systemImageName: "sparkles"
        )
    }
}
