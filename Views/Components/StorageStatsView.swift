import SwiftUI

struct StorageStatsView: View {
    let usedSpace: Int64
    let totalSpace: Int64

    @ObservedObject private var themeManager = ThemeManager.shared

    private var usedPercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace)
    }

    private var freeSpace: Int64 {
        totalSpace - usedSpace
    }

    var body: some View {
        let palette = themeManager.palette
        VStack(spacing: 16) {
            // Título
            HStack {
                Image(systemName: "internaldrive")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.accentGradient)

                Text("Storage")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(palette.primaryText)

                Spacer()
            }

            HStack(spacing: 20) {
                // Gráfico circular
                ZStack {
                    Circle()
                        .stroke(palette.secondaryText.opacity(0.2), lineWidth: 12)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: usedPercentage)
                        .stroke(
                            LinearGradient(
                                colors: palette.accent,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .shadow(
                            color: palette.glow ? palette.glowColor.opacity(0.7) : .clear,
                            radius: palette.glow ? 8 : 0
                        )

                    VStack(spacing: 2) {
                        Text("\(Int(usedPercentage * 100))%")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(palette.primaryText)
                        Text("used")
                            .font(.system(size: 10))
                            .foregroundColor(palette.secondaryText)
                    }
                }

                // Estatísticas
                VStack(alignment: .leading, spacing: 8) {
                    StatRow(
                        label: "Used",
                        value: FileSystemHelper.shared.formatBytes(usedSpace),
                        color: .blue
                    )

                    StatRow(
                        label: "Free",
                        value: FileSystemHelper.shared.formatBytes(freeSpace),
                        color: .green
                    )

                    StatRow(
                        label: "Total",
                        value: FileSystemHelper.shared.formatBytes(totalSpace),
                        color: .gray
                    )
                }
            }
        }
        .padding(20)
        .themedSurface(palette)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let color: Color

    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: 12))
                .foregroundColor(themeManager.palette.secondaryText)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.palette.primaryText)
        }
    }
}
