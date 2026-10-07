import SwiftUI

/// Decide se as boas-vindas aparecem. O app vive só na barra de menus (sem Dock
/// nem janela), então logo depois de instalar a pessoa não vê nada e não sabe
/// onde ele foi parar. Aparece sempre que um instalador abre o app
/// (`--welcome`, passado pelo install.sh e pelo postinstall do .pkg) e na
/// primeira execução de todas; abrir o app à mão depois disso não mostra nada.
enum WelcomeGate {
    static let launchArgument = "--welcome"
    /// O install.sh rodado pelo botão Atualizar reabre o app com isto.
    static let updatedArgument = "--updated"
    static let shownKey = "welcomeShown"

    static func shouldShow(arguments: [String], environment: [String: String], defaults: UserDefaults) -> Bool {
        switch environment["MACLIMPO_WELCOME"] {
        case "1": return true
        case "0": return false
        default: break
        }
        // Retratos e aberturas de desenvolvimento não devem ganhar um balão por cima.
        if environment.keys.contains(where: { $0.hasPrefix("MACLIMPO_SNAPSHOT") || $0.hasPrefix("MACLIMPO_XRAY") || $0 == "MACLIMPO_OPEN_XRAY" }) {
            return false
        }
        return arguments.contains(launchArgument) || arguments.contains(updatedArgument) || !defaults.bool(forKey: shownKey)
    }
}

/// Balão que aponta para o ícone na barra de menus logo depois da instalação —
/// ou, depois de uma atualização pelo app, que confirma a versão nova.
struct WelcomeView: View {
    /// Versão recém-instalada pelo botão Atualizar; `nil` numa instalação.
    var updatedTo: String?
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let updatedTo {
                        Text("MAC-LIMPO was updated").font(.headline)
                        Text("Version \(updatedTo) is installed and running").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Welcome to MAC-LIMPO").font(.headline)
                        Text("Installed and running").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            (updatedTo == nil
                ? Text("MAC-LIMPO lives here in the menu bar — there's no Dock icon or main window. Click this icon anytime to scan your Mac and free up space.")
                : Text("Same place as always: click this icon in the menu bar to scan your Mac and free up space."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Got It", action: onDismiss)
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open MAC-LIMPO", action: onOpen)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(16)
        .frame(width: 320)
    }
}
