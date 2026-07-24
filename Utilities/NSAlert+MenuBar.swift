import AppKit

extension NSAlert {
    /// Exibe o alerta garantindo que ele fique acima do popover do menu bar.
    ///
    /// O popover é criado com `behavior = .transient`, o que o coloca no nível
    /// `.popUpMenu` — acima de qualquer janela normal. Um `NSAlert` abre em nível
    /// normal, portanto *atrás* do popover e invisível, enquanto `runModal()`
    /// bloqueia a main thread esperando uma resposta que o usuário não tem como
    /// dar. O sintoma é a aplicação inteira travada sem nada na tela explicando
    /// o porquê.
    ///
    /// Use este método em vez de `runModal()` em qualquer alerta alcançável a
    /// partir do popover.
    @discardableResult
    func runModalAboveMenuBarPopover() -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        return runModal()
    }
}
