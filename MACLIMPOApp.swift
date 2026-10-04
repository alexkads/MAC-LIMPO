import AppKit
import SwiftUI

@main
struct MACLIMPOApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var diskXRayWindow: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        // Garante instância única
        if let bundleID = Bundle.main.bundleIdentifier {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if runningApps.count > 1 {
                // Ativa a instância existente
                for app in runningApps {
                    if app != NSRunningApplication.current {
                        app.activate(options: [])
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
        popover.contentSize = NSSize(width: 420, height: 700)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView(onOpenDiskXRay: { [weak self] in
            self?.openDiskXRayWindow()
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

    func openDiskXRayWindow() {
        // Se a janela já existe, apenas traz para frente
        if let window = diskXRayWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Cria nova janela
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Disk X-Ray — MAC-LIMPO"
        window.center()
        window.isReleasedWhenClosed = false

        let xRayView = DiskXRayWindowView(onClose: { [weak self] in
            self?.diskXRayWindow?.close()
        })

        window.contentView = NSHostingView(rootView: xRayView)
        window.makeKeyAndOrderFront(nil)

        // Ativa a aplicação
        NSApp.activate(ignoringOtherApps: true)

        diskXRayWindow = window
    }
}
