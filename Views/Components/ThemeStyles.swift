// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import SwiftUI

// Comportamento visual por tema, num lugar só. As views pedem "botão
// secundário", "botão principal", "controle" ou "superfície de conteúdo" e o
// tema decide o material — no Liquid Glass, as APIs nativas de vidro.
//
// Regras do Liquid Glass seguidas aqui (documentação da Apple, "Applying
// Liquid Glass to custom views"):
// - vidro em controles e navegação, não em conteúdo: cards ficam com
//   preenchimento semântico, para não ter vidro sobre o vidro do popover;
// - `glassEffect` aplicado depois do padding/conteúdo;
// - `.interactive()` só em componentes que respondem a toque/clique;
// - o vidro nativo já se adapta a Reduzir Transparência e Aumentar Contraste;
//   os preenchimentos de conteúdo fazem o mesmo à mão.

extension ThemePalette {
    var isGlass: Bool { surfaceStyle == .glass }
}

extension View {
    /// Botão secundário (ícones do cabeçalho, Analyze, Quit…).
    @ViewBuilder
    func themedSecondaryButton(_ palette: ThemePalette) -> some View {
        if palette.isGlass {
            buttonStyle(.glass)
        } else {
            buttonStyle(.plain)
        }
    }

    /// Botão principal da tela (Clean All, confirmar).
    @ViewBuilder
    func themedProminentButton(_ palette: ThemePalette) -> some View {
        if palette.isGlass {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.plain)
        }
    }

    /// Botão de ação em diálogos, que nos outros temas usa `.borderedProminent`.
    @ViewBuilder
    func themedDialogButton(_ palette: ThemePalette) -> some View {
        if palette.isGlass {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Botão secundário de diálogo (Cancelar): vidro no Liquid Glass, o padrão
    /// do sistema nos demais.
    @ViewBuilder
    func themedDialogSecondaryButton(_ palette: ThemePalette) -> some View {
        if palette.isGlass {
            buttonStyle(.glass)
        } else {
            self
        }
    }

    /// Superfície de um controle (campo de busca): vidro no Liquid Glass,
    /// superfície do tema nos demais.
    func themedControlSurface(_ palette: ThemePalette, cornerRadius: CGFloat = 12) -> some View {
        modifier(ControlSurface(palette: palette, cornerRadius: cornerRadius))
    }

    /// Agrupa controles de vidro vizinhos (eles se fundem e se transformam
    /// juntos); nos outros temas não faz nada.
    @ViewBuilder
    func themedGlassGroup(_ palette: ThemePalette, spacing: CGFloat = 8) -> some View {
        if palette.isGlass {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

private struct ControlSurface: ViewModifier {
    let palette: ThemePalette
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if palette.isGlass {
            if reduceTransparency {
                content.background(
                    Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius)
                )
            } else {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
            }
        } else {
            content.themedSurface(palette, cornerRadius: cornerRadius)
        }
    }
}

/// Superfície de conteúdo no Liquid Glass: preenchimento semântico, sem vidro,
/// sombra ou gradiente; com Aumentar Contraste ganha um contorno.
struct GlassContentSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(reduceTransparency
                        ? Color(nsColor: .controlBackgroundColor)
                        : Color(nsColor: .quaternarySystemFill))
            )
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
            }
    }
}
