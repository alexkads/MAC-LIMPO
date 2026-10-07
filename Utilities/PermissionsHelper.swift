import AppKit
import Foundation

class PermissionsHelper {
    /// Verifica se o app tem Full Disk Access.
    ///
    /// Sonda o `TCC.db` do usuário: ele sempre existe e só é legível com FDA.
    /// O probe antigo era o `History.db` do Safari, que **não existe** em quem
    /// nunca abriu o Safari — nesse caso o app se achava sem FDA para sempre.
    /// Mantemos o Safari como segunda tentativa.
    ///
    /// `isReadableFile` usa `access(2)`, que responde EPERM sem abrir o diálogo
    /// do TCC — de propósito: esta checagem roda antes de cada scan e não pode
    /// ser ela mesma uma fonte de pedidos de permissão.
    static func hasFullDiskAccess() -> Bool {
        let fileManager = FileManager.default
        let probes = [
            NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db",
            NSHomeDirectory() + "/Library/Safari/History.db"
        ]
        return probes.contains { fileManager.isReadableFile(atPath: $0) }
    }

    /// Igual a `hasFullDiskAccess()`, mas com o resultado memoizado por alguns
    /// segundos. Um scan completo consulta isto dezenas de vezes (uma por
    /// service) e o resultado não muda no meio de uma varredura.
    static func hasFullDiskAccessCached() -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached, Date().timeIntervalSince(cached.checkedAt) < cacheTTL {
            return cached.granted
        }
        let granted = hasFullDiskAccess()
        cached = (granted, Date())
        return granted
    }

    /// Invalida o cache — chame depois de mandar o usuário às System Settings.
    static func invalidateFullDiskAccessCache() {
        cacheLock.lock()
        cached = nil
        cacheLock.unlock()
    }

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cached: (granted: Bool, checkedAt: Date)?
    private static let cacheTTL: TimeInterval = 10

    /// Prefixos (relativos ao home) que o macOS protege por TCC.
    ///
    /// `~/Library/Containers` e `~/Library/Group Containers` são os críticos:
    /// sem Full Disk Access, **cada container** que o app toca abre um diálogo
    /// "deseja acessar dados de outros apps" — e há centenas deles num Mac
    /// usado. Era isso que fazia o scan virar uma fila infinita de pedidos de
    /// permissão com os cards presos no spinner.
    private static let protectedHomePrefixes = [
        "/Library/Containers",
        "/Library/Group Containers",
        "/Library/Safari",
        "/Library/Mail",
        "/Library/Messages",
        "/Library/Cookies",
        "/Library/Suggestions",
        "/Library/Metadata/CoreSpotlight",
        "/Library/Application Support/CloudDocs",
        "/Library/Application Support/AddressBook",
        "/Library/Application Support/CallHistoryDB",
        "/Library/Application Support/com.apple.TCC"
    ]

    /// `true` se ler `path` exige Full Disk Access. Aceita path já expandido ou
    /// com `~`.
    static func requiresFullDiskAccess(path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        let home = NSHomeDirectory()
        guard expanded.hasPrefix(home) else { return false }
        let relative = String(expanded.dropFirst(home.count))
        return protectedHomePrefixes.contains { relative == $0 || relative.hasPrefix($0 + "/") }
    }

    /// Abre o painel de Full Disk Access nas System Settings
    @MainActor
    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// Mostra alerta pedindo Full Disk Access
    @MainActor
    static func requestFullDiskAccess(onGrant: @escaping @MainActor @Sendable () -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Full Disk Access Required")
        alert.informativeText = String(localized: """
        MAC-LIMPO needs Full Disk Access to clean every area of the system and free up as much space as possible.

        Without this permission: ~5–40 GB freed
        With this permission: ~50–200 GB freed

        Do you want to open System Settings to enable it?
        """)
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Continue Without Permission"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        alert.icon = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: String(localized: "Security"))

        let response = alert.runModalAboveMenuBarPopover()

        switch response {
        case .alertFirstButtonReturn:
            // Abre as configurações
            openFullDiskAccessSettings()

            // Mostra alerta de follow-up
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showFollowUpAlert(onGrant: onGrant)
            }

        case .alertSecondButtonReturn:
            // Continua sem permissão
            onGrant()

        default:
            // Cancela
            break
        }
    }

    /// Mostra alerta de follow-up após abrir as configurações
    @MainActor
    private static func showFollowUpAlert(onGrant: @escaping @MainActor @Sendable () -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Enable Full Disk Access")
        alert.informativeText = String(localized: """
        In the System Settings window that just opened:

        1. Click the lock and authenticate
        2. Click the “+” button
        3. Go to Applications and select MAC-LIMPO
        4. Turn on the switch next to MAC-LIMPO
        5. Click “Done” in this alert when you’re finished

        After that, MAC-LIMPO will be able to free up much more space!
        """)
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Done — I’ve Enabled It"))
        alert.addButton(withTitle: String(localized: "Skip for Now"))

        let response = alert.runModalAboveMenuBarPopover()

        if response == .alertFirstButtonReturn {
            // Verifica se realmente tem acesso agora
            invalidateFullDiskAccessCache()
            if hasFullDiskAccess() {
                let successAlert = NSAlert()
                successAlert.messageText = String(localized: "✅ Full Disk Access Enabled!")
                successAlert.informativeText = String(
                    localized: "You can now free up much more space. Run the cleaning again for better results."
                )
                successAlert.alertStyle = .informational
                successAlert.addButton(withTitle: String(localized: "OK"))
                successAlert.runModalAboveMenuBarPopover()
            } else {
                let warningAlert = NSAlert()
                warningAlert.messageText = String(localized: "⚠️ Permission Not Detected")
                warningAlert.informativeText = String(localized: """
                Full Disk Access wasn’t detected yet. Make sure you added MAC-LIMPO and turned on its switch.

                You can continue without this permission, but less space will be freed.
                """)
                warningAlert.alertStyle = .warning
                warningAlert.addButton(withTitle: String(localized: "OK"))
                warningAlert.runModalAboveMenuBarPopover()
            }
        }

        onGrant()
    }
}
