import SwiftUI

/// Confirmação de limpeza mostrada **dentro** do popover (overlay SwiftUI), no lugar
/// do antigo `NSAlert`. Como não é uma janela nativa, não rouba o foco nem fecha o
/// popover — o usuário confirma, vê o progresso e o resultado sem o popover sumir.
struct CleaningConfirmationView: View {
    let request: ConfirmationRequest
    let onConfirm: (_ dontAskAgain: Bool) -> Void
    let onCancel: () -> Void

    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var dontAskAgain = false

    var body: some View {
        let palette = themeManager.palette
        ZStack {
            // Scrim SwiftUI (não é janela nativa; não fecha o popover).
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 18) {
                // Ícone
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "trash")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.orange)
                }

                Text(request.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(palette.primaryText)
                    .multilineTextAlignment(.center)

                Text(request.message)
                    .font(.system(size: 13))
                    .foregroundColor(palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Não perguntar de novo nesta sessão", isOn: $dontAskAgain)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .foregroundColor(palette.secondaryText)

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancelar")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)

                    Button(action: { onConfirm(dontAskAgain) }) {
                        Text("Limpar")
                            .frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(28)
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(palette.glow ? palette.surface : Color(NSColor.windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(palette.surfaceStroke, lineWidth: palette.glow ? 1.5 : 0)
                    )
                    .shadow(
                        color: palette.glow ? palette.glowColor.opacity(0.5) : .black.opacity(0.3),
                        radius: 30
                    )
            )
        }
        .transition(.opacity)
    }
}
