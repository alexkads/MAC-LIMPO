import Foundation
import FoundationModels

/// Availability exposed to the UI without leaking Foundation Models details.
enum AppleIntelligenceAvailability: Equatable, Sendable {
    case available
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case unavailable

    var message: String {
        switch self {
        case .available:
            "Apple Intelligence is ready on this Mac."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in System Settings to generate local insights."
        case .deviceNotEligible:
            "This Mac does not support Apple Intelligence."
        case .modelNotReady:
            "The on-device model is still preparing. Try again later."
        case .unavailable:
            "Apple Intelligence is currently unavailable."
        }
    }
}

/// Local-only intelligence boundary for MAC-LIMPO.
///
/// The service sends only aggregate category names and byte counts to Apple's
/// on-device model. It never includes file paths, filenames or account data.
actor AppleIntelligenceService {
    static let shared = AppleIntelligenceService()

    private let model = SystemLanguageModel.default

    func availability() -> AppleIntelligenceAvailability {
        switch model.availability {
        case .available:
            .available
        case .unavailable(.appleIntelligenceNotEnabled):
            .appleIntelligenceNotEnabled
        case .unavailable(.deviceNotEligible):
            .deviceNotEligible
        case .unavailable(.modelNotReady):
            .modelNotReady
        case .unavailable:
            .unavailable
        }
    }

    /// Generates a concise local recommendation from aggregate scan data.
    func generateStorageInsight(
        scanResults: [ScanResult],
        totalDiskSpace: Int64,
        usedDiskSpace: Int64
    ) async throws -> String {
        guard availability() == .available else {
            throw AppleIntelligenceError.unavailable(availability())
        }

        let rankedCategories = scanResults
            .filter { $0.estimatedSize > 0 }
            .sorted { $0.estimatedSize > $1.estimatedSize }
            .prefix(8)
            .map { "\($0.category.rawValue): \($0.formattedSize)" }
            .joined(separator: ", ")

        let usedPercent = totalDiskSpace > 0
            ? Int((Double(usedDiskSpace) / Double(totalDiskSpace)) * 100)
            : 0

        let session = LanguageModelSession(instructions: """
            You are MAC-LIMPO's on-device storage assistant. Analyze only the aggregate
            storage data provided by the app. Do not invent files, paths, causes or facts.
            Answer in the user's language when possible. Give one short recommendation,
            mention the largest category, and remind the user to review before deleting.
            Keep the answer under 80 words and do not use markdown tables.
            """)

        let prompt = """
        Disk usage: \(usedPercent)%.
        Largest categories by estimated reclaimable size: \(rankedCategories.isEmpty ? "none found" : rankedCategories).
        Provide a concise, practical storage insight.
        """

        return try await session.respond(to: prompt).content
    }
}

enum AppleIntelligenceError: LocalizedError, Sendable {
    case unavailable(AppleIntelligenceAvailability)

    var errorDescription: String? {
        switch self {
        case let .unavailable(status):
            status.message
        }
    }
}
