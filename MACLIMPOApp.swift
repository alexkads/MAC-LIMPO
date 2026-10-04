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

        // Desenvolvimento: abre o Disk X-Ray direto (sem clicar no menu bar) e,
        // com MACLIMPO_SNAPSHOT=<arquivo.png>, salva um retrato da janela depois
        // de MACLIMPO_SNAPSHOT_DELAY segundos (padrão 90) — sem precisar da
        // permissão de Gravação de Tela.
        let environment = ProcessInfo.processInfo.environment
        if let appearance = environment["MACLIMPO_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        }
        // MACLIMPO_SNAPSHOT_POPOVER=<arquivo.png>: retrato do popover (fora da tela)
        // depois de MACLIMPO_SNAPSHOT_DELAY segundos.
        if let popoverPath = environment["MACLIMPO_SNAPSHOT_POPOVER"] {
            let delay = Double(environment["MACLIMPO_SNAPSHOT_DELAY"] ?? "") ?? 90
            let window = NSWindow(
                contentRect: NSRect(x: -4000, y: -4000, width: 420, height: 700),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            // O cacheDisplay não desenha o fundo da janela (é do frame view);
            // o fundo vai na própria hierarquia para o retrato não sair branco.
            window.contentView = NSHostingView(rootView: MenuBarView().background(Color(nsColor: .windowBackgroundColor)))
            window.appearance = NSApp.appearance
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
            window.orderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let view = window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: popoverPath))
                window.orderOut(nil)
            }
        }
        if environment["MACLIMPO_OPEN_XRAY"] == "1" {
            openDiskXRayWindow()
            if let snapshotPath = environment["MACLIMPO_SNAPSHOT"] {
                let delay = Double(environment["MACLIMPO_SNAPSHOT_DELAY"] ?? "") ?? 90
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.snapshotDiskXRay(to: snapshotPath)
                }
            }
        }
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

    private func snapshotDiskXRay(to path: String) {
        // A moldura (superview do conteúdo) inclui a barra de título e a toolbar.
        guard let content = diskXRayWindow?.contentView,
              case let view = content.superview ?? content,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
            backing: .buffered,
            defer: false
        )

        window.title = "Disk X-Ray — MAC-LIMPO"
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified

        let xRayView = DiskXRayWindowView(onClose: { [weak self] in
            self?.diskXRayWindow?.close()
        })

        // NSHostingController com a ponte de toolbar: o `.toolbar` do SwiftUI
        // vira a NSToolbar desta janela (com o visual Liquid Glass do sistema),
        // e o `.navigationTitle` vira o título.
        let controller = NSHostingController(rootView: xRayView)
        controller.sceneBridgingOptions = [.toolbars, .title]
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1040, height: 780))
        window.center()
        // A varredura guarda milhões de itens; ao fechar, solta tudo.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.diskXRayWindow?.contentViewController = nil
                self?.diskXRayWindow = nil
            }
        }
        window.makeKeyAndOrderFront(nil)

        // Ativa a aplicação
        NSApp.activate(ignoringOtherApps: true)

        diskXRayWindow = window
    }
}
