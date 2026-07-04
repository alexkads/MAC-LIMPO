import SwiftUI

/// Seletor de tema: uma linha de "swatches" clicáveis. O selecionado ganha um
/// anel de destaque. Muda o tema globalmente via `ThemeManager.shared`.
struct ThemePickerView: View {
    @ObservedObject var themeManager: ThemeManager

    var body: some View {
        let palette = themeManager.palette
        VStack(alignment: .leading, spacing: 8) {
            Text("Theme")
                .font(.system(size: 14))
                .foregroundColor(palette.primaryText)

            HStack(spacing: 10) {
                ForEach(AppTheme.allCases) { theme in
                    swatch(for: theme, isSelected: theme == themeManager.theme)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
    }

    private func swatch(for theme: AppTheme, isSelected: Bool) -> some View {
        let gradient = LinearGradient(colors: theme.swatch, startPoint: .topLeading, endPoint: .bottomTrailing)
        return VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(gradient)
                    .frame(width: 46, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.white.opacity(isSelected ? 0.9 : 0.15), lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(
                        color: theme.swatch.first?.opacity(isSelected ? 0.7 : 0) ?? .clear,
                        radius: isSelected ? 8 : 0
                    )

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
            }
            Text(theme.displayName)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? themeManager.palette.primaryText : themeManager.palette.secondaryText)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                themeManager.theme = theme
            }
        }
    }
}

extension View {
    /// Aplica o "chrome" de superfície (card) conforme o tema. No Classic reproduz
    /// o visual original; nos temas neon usa preenchimento translúcido, borda e glow.
    @ViewBuilder
    func themedSurface(_ palette: ThemePalette, cornerRadius: CGFloat = 16, hovered: Bool = false) -> some View {
        if palette.glow {
            background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(palette.surfaceStroke, lineWidth: palette.surfaceStrokeWidth)
            )
            .shadow(color: palette.glowColor.opacity(hovered ? 0.55 : 0.28), radius: hovered ? 16 : 10)
        } else {
            background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(palette.surface)
                    .shadow(color: .black.opacity(hovered ? 0.15 : 0.08), radius: hovered ? 12 : 8, y: hovered ? 6 : 4)
            )
        }
    }
}
