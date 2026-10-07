import SwiftUI

struct CleaningCategoryCard: View {
    let category: CleaningCategory
    let estimatedSize: String
    let isScanning: Bool
    let scanningStatus: String?
    /// Limpeza desta categoria em andamento: mostra spinner no card e desativa
    /// o clique — os demais cards continuam clicáveis (limpezas simultâneas).
    var isCleaning = false
    let action: () -> Void

    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Cor/gradiente do ícone: por categoria, ou o accent do tema (ex.: Matrix).
    private var iconGradient: LinearGradient {
        themeManager.palette.usesCategoryColors ? category.gradient : themeManager.palette.accentGradient
    }

    private var iconGlowColor: Color {
        themeManager.palette.usesCategoryColors ? category.color : themeManager.palette.glowColor
    }

    var body: some View {
        let palette = themeManager.palette
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(iconGradient)
                        .frame(width: 50, height: 50)
                        .shadow(
                            color: palette.isGlass ? .clear
                                : (palette.glow ? iconGlowColor.opacity(0.8) : .black.opacity(0.2)),
                            radius: palette.glow ? (isHovered ? 14 : 9) : (isHovered ? 8 : 4),
                            y: palette.glow ? 0 : (isHovered ? 4 : 2)
                        )

                    Image(systemName: category.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
                .scaleEffect(isHovered && !reduceMotion ? 1.05 : 1.0)

                VStack(alignment: .leading, spacing: 4) {
                    Text(category.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(palette.primaryText)

                    Text(category.description)
                        .font(.system(size: 12))
                        .foregroundColor(palette.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                if isCleaning {
                    HStack(spacing: 8) {
                        Text("Cleaning…")
                            .font(.system(size: 11))
                            .foregroundColor(palette.secondaryText)
                            .lineLimit(1)
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    }
                } else if isScanning {
                    HStack(spacing: 8) {
                        if let status = scanningStatus {
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundColor(palette.secondaryText)
                                .lineLimit(1)
                        }
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    }
                } else {
                    Text(estimatedSize)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if palette.isGlass {
                                Capsule().fill(palette.usesCategoryColors ? category.color : Color.accentColor)
                            } else {
                                Capsule().fill(iconGradient)
                            }
                        }
                }
            }
            .padding(16)
            .themedSurface(palette, hovered: isHovered)
            .overlay {
                if palette.isGlass {
                    // Hover sem borda colorida: um realce do próprio preenchimento.
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
                } else {
                    // Realce de borda no hover (accent/categoria).
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            iconGradient.opacity(isHovered ? (palette.glow ? 0.9 : 0.5) : 0),
                            lineWidth: 2
                        )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isCleaning)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(
            "\(category.displayName), \(isCleaning ? String(localized: "cleaning") : isScanning ? String(localized: "scanning") : estimatedSize)"
        )
        .accessibilityHint("Cleans \(category.displayName)")
    }
}
