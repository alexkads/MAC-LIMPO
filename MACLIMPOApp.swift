import SwiftUI
import AppKit

@main
struct MACLIMPOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var treemapWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Garante instância única
        if let bundleID = Bundle.main.bundleIdentifier {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if runningApps.count > 1 {
                // Ativa a instância existente
                for app in runningApps {
                    if app != NSRunningApplication.current {
                        app.activate(options: .activateIgnoringOtherApps)
                        break
                    }
                }
                // Encerra esta instância
                NSApp.terminate(nil)
                return
            }
        }

        // Oculta o ícone do Dock
        NSApp.setActivationPolicy(.accessory)
        
        // Cria o item no menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            // Ícone do menu bar (SF Symbol)
            button.image = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: "MAC-LIMPO")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Configura o popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView(onOpenTreemap: { [weak self] in
            self?.openTreemapWindow()
        }))
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Ativa a aplicação para receber eventos
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    func openTreemapWindow() {
        // Se a janela já existe, apenas traz para frente
        if let window = treemapWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Cria nova janela
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Disk Map - MAC-LIMPO"
        window.center()
        window.isReleasedWhenClosed = false
        
        // Cria a view do treemap sem o overlay de fundo
        let treemapView = TreemapWindowView(onClose: { [weak self] in
            self?.treemapWindow?.close()
        })
        
        window.contentView = NSHostingView(rootView: treemapView)
        window.makeKeyAndOrderFront(nil)
        
        // Ativa a aplicação
        NSApp.activate(ignoringOtherApps: true)
        
        treemapWindow = window
    }
}
