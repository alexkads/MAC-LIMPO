import SwiftUI

/// Paleta e estilo de um tema. Descreve tudo que as views precisam para se
/// pintar de forma coesa, sem espalhar cores mágicas pela UI.
struct ThemePalette {
    /// Fundo da janela (gradiente atrás de tudo). Vazio = usa o material do popover.
    let backgroundColors: [Color]
    /// Preenchimento dos cards / superfícies.
    let surface: Color
    let surfaceStroke: Color
    let surfaceStrokeWidth: CGFloat
    /// Texto.
    let primaryText: Color
    let secondaryText: Color
    /// Gradiente de destaque (título, botão Clean All, badges).
    let accent: [Color]
    /// Efeito neon (glow) em torno de superfícies/ícones — o coração do Cyberpunk.
    let glow: Bool
    let glowColor: Color
    /// Fonte: monoespaçada dá o ar techy dos temas neon.
    let fontDesign: Font.Design
    /// Se `true`, mantém as cores por-categoria; se `false`, tinge tudo no accent.
    let usesCategoryColors: Bool

    var accentGradient: LinearGradient {
        LinearGradient(colors: accent, startPoint: .leading, endPoint: .trailing)
    }

    var backgroundView: some View {
        Group {
            if backgroundColors.isEmpty {
                Color.clear
            } else {
                LinearGradient(colors: backgroundColors, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
    }
}

/// Temas disponíveis. `classic` é exatamente o visual original — nada se perde.
enum AppTheme: String, CaseIterable, Identifiable {
    case classic
    case cyberpunk
    case matrix

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .classic: "Classic"
        case .cyberpunk: "Cyberpunk"
        case .matrix: "Matrix"
        }
    }

    /// Cores mostradas no seletor (swatch).
    var swatch: [Color] {
        palette.accent
    }

    var palette: ThemePalette {
        switch self {
        case .classic:
            return ThemePalette(
                backgroundColors: [],
                surface: Color(NSColor.controlBackgroundColor),
                surfaceStroke: .clear,
                surfaceStrokeWidth: 2,
                primaryText: .primary,
                secondaryText: .secondary,
                accent: [.blue, .purple],
                glow: false,
                glowColor: .clear,
                fontDesign: .default,
                usesCategoryColors: true
            )

        case .cyberpunk:
            let cyan = Color(hex: "00F0FF")
            let magenta = Color(hex: "FF2E97")
            return ThemePalette(
                backgroundColors: [Color(hex: "0B0F1A"), Color(hex: "13092B"), Color(hex: "05070D")],
                surface: Color(hex: "0E1524").opacity(0.85),
                surfaceStroke: cyan.opacity(0.55),
                surfaceStrokeWidth: 1.5,
                primaryText: Color(hex: "E7FBFF"),
                secondaryText: cyan.opacity(0.65),
                accent: [cyan, magenta],
                glow: true,
                glowColor: cyan,
                fontDesign: .monospaced,
                usesCategoryColors: true
            )

        case .matrix:
            let green = Color(hex: "00FF7F")
            let deepGreen = Color(hex: "00A86B")
            return ThemePalette(
                backgroundColors: [Color(hex: "020A06"), Color(hex: "04140C"), Color(hex: "010402")],
                surface: Color(hex: "05140C").opacity(0.85),
                surfaceStroke: green.opacity(0.5),
                surfaceStrokeWidth: 1.5,
                primaryText: Color(hex: "CFFFE5"),
                secondaryText: green.opacity(0.6),
                accent: [green, deepGreen],
                glow: true,
                glowColor: green,
                fontDesign: .monospaced,
                usesCategoryColors: false
            )
        }
    }
}

/// Fonte única de verdade do tema atual. Persiste a escolha em UserDefaults.
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let storageKey = "selectedTheme"

    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.storageKey) }
    }

    var palette: ThemePalette {
        theme.palette
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        theme = stored.flatMap(AppTheme.init(rawValue:)) ?? .classic
    }
}
