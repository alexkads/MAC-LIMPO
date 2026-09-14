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
    private static var cached: (granted: Bool, checkedAt: Date)?
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
    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// Mostra alerta pedindo Full Disk Access
    static func requestFullDiskAccess(onGrant: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Full Disk Access Necessário"
        alert.informativeText = """
        O MAC-LIMPO precisa de Full Disk Access para limpar todas as áreas do sistema e liberar o máximo de espaço possível.

        Sem essa permissão: ~5-40GB liberados
        Com essa permissão: ~50-200GB liberados

        Deseja abrir as configurações para habilitar?
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Abrir Configurações")
        alert.addButton(withTitle: "Continuar Sem Permissão")
        alert.addButton(withTitle: "Cancelar")

        alert.icon = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Security")

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
    private static func showFollowUpAlert(onGrant: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Habilite Full Disk Access"
        alert.informativeText = """
        Nas configurações que acabaram de abrir:

        1. Clique no cadeado e autentique
        2. Clique no botão "+" 
        3. Navegue até Applications e selecione MAC-LIMPO
        4. Marque o checkbox ao lado de MAC-LIMPO
        5. Clique "Done" neste alerta quando terminar

        Depois disso, o MAC-LIMPO poderá limpar muito mais espaço!
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Done - Já Habilitei")
        alert.addButton(withTitle: "Pular Por Agora")

        let response = alert.runModalAboveMenuBarPopover()

        if response == .alertFirstButtonReturn {
            // Verifica se realmente tem acesso agora
            invalidateFullDiskAccessCache()
            if hasFullDiskAccess() {
                let successAlert = NSAlert()
                successAlert.messageText = "✅ Full Disk Access Habilitado!"
                successAlert.informativeText = "Agora você pode limpar muito mais espaço. Execute a limpeza novamente para melhores resultados."
                successAlert.alertStyle = .informational
                successAlert.addButton(withTitle: "OK")
                successAlert.runModalAboveMenuBarPopover()
            } else {
                let warningAlert = NSAlert()
                warningAlert.messageText = "⚠️ Permissão Não Detectada"
                warningAlert.informativeText = """
                Não detectamos Full Disk Access ainda. Certifique-se de ter adicionado o \
                MAC-LIMPO e marcado o checkbox.

                Você pode continuar sem essa permissão, mas liberará menos espaço.
                """
                warningAlert.alertStyle = .warning
                warningAlert.addButton(withTitle: "OK")
                warningAlert.runModalAboveMenuBarPopover()
            }
        }

        onGrant()
    }
}
