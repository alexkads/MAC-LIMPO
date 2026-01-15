import Foundation
import AppKit

class PermissionsHelper {
    
    /// Verifica se o app tem Full Disk Access
    static func hasFullDiskAccess() -> Bool {
        // Tenta acessar um diretório protegido que só é acessível com Full Disk Access
        let protectedPath = NSHomeDirectory() + "/Library/Safari/History.db"
        let fileManager = FileManager.default
        
        // Se conseguir verificar se o arquivo existe, tem acesso
        return fileManager.isReadableFile(atPath: protectedPath)
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
        
        let response = alert.runModal()
        
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
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Verifica se realmente tem acesso agora
            if hasFullDiskAccess() {
                let successAlert = NSAlert()
                successAlert.messageText = "✅ Full Disk Access Habilitado!"
                successAlert.informativeText = "Agora você pode limpar muito mais espaço. Execute a limpeza novamente para melhores resultados."
                successAlert.alertStyle = .informational
                successAlert.addButton(withTitle: "OK")
                successAlert.runModal()
            } else {
                let warningAlert = NSAlert()
                warningAlert.messageText = "⚠️ Permissão Não Detectada"
                warningAlert.informativeText = "Não detectamos Full Disk Access ainda. Certifique-se de ter adicionado o MAC-LIMPO e marcado o checkbox.\n\nVocê pode continuar sem essa permissão, mas liberará menos espaço."
                warningAlert.alertStyle = .warning
                warningAlert.addButton(withTitle: "OK")
                warningAlert.runModal()
            }
        }
        
        onGrant()
    }
}
