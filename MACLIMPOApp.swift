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
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
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
}
