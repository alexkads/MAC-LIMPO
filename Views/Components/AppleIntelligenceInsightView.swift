import SwiftUI

struct AppleIntelligenceInsightView: View {
    let insight: String?
    let status: AppleIntelligenceAvailability?
    let isGenerating: Bool
    let generateInsight: () -> Void

    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "apple.intelligence")
                    .foregroundStyle(themeManager.palette.accentGradient)

                Text("Apple Intelligence")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.palette.primaryText)

                Spacer()

                Button(action: generateInsight) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(insight == nil ? "Analyze" : "Refresh")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .themedSecondaryButton(themeManager.palette)
                .foregroundStyle(themeManager.palette.accentGradient)
                .disabled(isGenerating)
                .accessibilityLabel(isGenerating ? "Generating recommendation" : "Generate storage recommendation")
            }

            if let insight {
                Text(insight)
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(status?.message ?? "Generate a private, on-device storage recommendation.")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .themedSurface(themeManager.palette, cornerRadius: 12)
    }
}
