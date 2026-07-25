import SwiftUI

/// Barra de progresso inline, ancorada na base do popover. Diferente de uma modal,
/// **não** cobre a UI com backdrop nem captura cliques fora da própria barra —
/// o usuário continua navegando/rolando enquanto a limpeza roda.
struct CleaningProgressView: View {
    let category: CleaningCategory
    @Binding var isShowing: Bool
    let progress: Double
    let currentOperation: String

    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let palette = themeManager.palette
        VStack {
            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    // Ícone da categoria
                    ZStack {
                        Circle()
                            .fill(category.gradient)
                            .frame(width: 32, height: 32)

                        Image(systemName: category.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cleaning \(category.rawValue)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(palette.primaryText)
                            .lineLimit(1)

                        Text(currentOperation)
                            .font(.system(size: 11))
                            .foregroundColor(palette.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(palette.secondaryText)

                    // Cancelar
                    Button(action: { isShowing = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(palette.secondaryText.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Cancel")
                }

                // Barra de progresso
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(category.gradient)
                            .frame(width: max(0, geometry.size.width * progress), height: 6)
                            .animation(.linear(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 6)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(palette.glow ? palette.surface : Color(NSColor.windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(palette.surfaceStroke, lineWidth: palette.glow ? 1.5 : 0)
                    )
                    .shadow(
                        color: palette.glow ? palette.glowColor.opacity(0.4) : .black.opacity(0.25),
                        radius: 16, y: 4
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        // Só a barra na base recebe toques; o resto do popover segue interativo.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(true)
    }
}
