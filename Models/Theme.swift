import SwiftUI

/// Como as superfícies de um tema são construídas. Não é só cor: o Liquid
/// Glass troca o tipo de material e o estilo dos controles.
enum SurfaceStyle {
    /// Preenchimento opaco com sombra suave (Classic).
    case solid
    /// Preenchimento translúcido escuro, borda e brilho neon (Cyberpunk, Matrix).
    case neon
    /// Liquid Glass nativo: controles e navegação em vidro (`glassEffect`,
    /// `.glass`/`.glassProminent`), conteúdo em preenchimentos semânticos.
    case glass
}

/// Paleta e estilo de um tema. Descreve tudo que as views precisam para se
/// pintar de forma coesa, sem espalhar cores mágicas pela UI.
struct ThemePalette {
    /// Tipo de superfície (material) do tema.
    let surfaceStyle: SurfaceStyle
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

/// Temas disponíveis. `liquidGlass` é o principal (padrão, todo nativo);
/// `classic` é exatamente o visual original — nada se perde. A ordem dos casos
/// é a ordem do seletor.
enum AppTheme: String, CaseIterable, Identifiable {
    case liquidGlass
    case classic
    case cyberpunk
    case matrix

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .classic: String(localized: "Classic")
        case .cyberpunk: String(localized: "Cyberpunk")
        case .matrix: String(localized: "Matrix")
        case .liquidGlass: String(localized: "Liquid Glass")
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
                surfaceStyle: .solid,
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
                surfaceStyle: .neon,
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
                surfaceStyle: .neon,
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

        case .liquidGlass:
            // Só cores semânticas: acompanham claro/escuro, contraste aumentado e
            // a cor de destaque escolhida nos Ajustes do Sistema. Sem fundo
            // próprio — o popover já é de vidro.
            return ThemePalette(
                surfaceStyle: .glass,
                backgroundColors: [],
                surface: Color(nsColor: .quaternarySystemFill),
                surfaceStroke: .clear,
                surfaceStrokeWidth: 0,
                primaryText: .primary,
                secondaryText: .secondary,
                accent: [.accentColor, .accentColor],
                glow: false,
                glowColor: .clear,
                fontDesign: .default,
                usesCategoryColors: true
            )
        }
    }
}

/// Fonte única de verdade do tema atual. Persiste a escolha em UserDefaults.
final class ThemeManager: ObservableObject, @unchecked Sendable {
    static let shared = ThemeManager()

    private static let storageKey = "selectedTheme"

    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.storageKey) }
    }

    var palette: ThemePalette {
        theme.palette
    }

    private init() {
        // Desenvolvimento: MACLIMPO_THEME escolhe o tema sem gravar a preferência
        // (o didSet não roda no init).
        if let forced = ProcessInfo.processInfo.environment["MACLIMPO_THEME"].flatMap(AppTheme.init(rawValue:)) {
            theme = forced
            return
        }
        // Sem escolha gravada (a preferência só é salva quando o usuário escolhe),
        // o padrão é o Liquid Glass.
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        theme = stored.flatMap(AppTheme.init(rawValue:)) ?? .liquidGlass
    }
}
