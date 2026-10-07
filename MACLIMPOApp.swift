import AppKit
import Combine
import SwiftUI
import UserNotifications

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
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var welcomePopover: NSPopover?
    var diskXRayWindow: NSWindow?
    private var updateObservation: AnyCancellable?

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
            button.image = Self.statusImage(badged: false)
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

        // Versão nova: ponto no ícone + faixa no popover + notificação (uma vez).
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = self
        }
        let updater = UpdateChecker.shared
        updateObservation = updater.$state.combineLatest(updater.$dismissedVersion)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.refreshStatusIcon() }
        updater.start()

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

        if WelcomeGate.shouldShow(arguments: CommandLine.arguments, environment: environment, defaults: .standard) {
            // O botão do status item só ganha janela e posição depois que a
            // barra de menus faz o layout.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showWelcome()
            }
        }
    }

    /// Boas-vindas logo depois de instalar: um balão saindo do próprio ícone
    /// mostra onde o app foi parar. Se o ícone não está à vista (atrás do
    /// notch, barra cheia ou desligado em Ajustes › Barra de Menus), um alerta
    /// no centro da tela diz onde procurar.
    func showWelcome() {
        UserDefaults.standard.set(true, forKey: WelcomeGate.shownKey)
        NSApp.activate(ignoringOtherApps: true)

        guard let button = statusItem.button, let barWindow = button.window, statusItem.isVisible,
              barWindow.occlusionState.contains(.visible),
              NSScreen.screens.contains(where: { $0.frame.contains(barWindow.frame) })
        else {
            showWelcomeAlert()
            return
        }

        let welcome = NSPopover()
        // Fica até a pessoa responder: o app acabou de abrir em segundo plano e
        // um clique em qualquer outro lugar fecharia um balão transitório.
        welcome.behavior = .applicationDefined
        let updated = CommandLine.arguments.contains(WelcomeGate.updatedArgument) ? UpdateChecker.currentVersion : nil
        welcome.contentViewController = NSHostingController(rootView: WelcomeView(
            updatedTo: updated,
            onOpen: { [weak self] in
                self?.closeWelcome()
                self?.togglePopover()
            },
            onDismiss: { [weak self] in self?.closeWelcome() }
        ))
        welcome.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        welcomePopover = welcome
    }

    private func showWelcomeAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Welcome to MAC-LIMPO")
        alert.informativeText = String(localized: """
        MAC-LIMPO lives in the menu bar — look for the trash icon at the top right of the screen. \
        There's no Dock icon or main window.

        Don't see it? The menu bar may be full or the icon hidden by the notch: hold ⌘ and drag \
        other icons aside, or allow MAC-LIMPO in System Settings › Menu Bar.
        """)
        alert.addButton(withTitle: String(localized: "Got It"))
        // Aberto em segundo plano, o pedido de ativação pode ser ignorado pelo
        // macOS; sem isto o alerta ficaria atrás da janela em uso.
        alert.window.level = .floating
        alert.runModal()
    }

    private func closeWelcome() {
        welcomePopover?.performClose(nil)
        welcomePopover = nil
    }

    // MARK: - Ícone e notificação de versão nova

    /// O ícone da barra de menus; com versão nova, ganha um ponto no canto
    /// (recortado do símbolo para continuar legível como imagem modelo).
    static func statusImage(badged: Bool) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: "MAC-LIMPO") else { return nil }
        guard badged else { return symbol }
        let size = symbol.size
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            let dot = NSRect(x: rect.maxX - size.width * 0.42, y: rect.maxY - size.height * 0.42,
                             width: size.width * 0.42, height: size.height * 0.42)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = String(localized: "MAC-LIMPO — update available")
        return image
    }

    private func refreshStatusIcon() {
        let pending = UpdateChecker.shared.hasPendingUpdate
        statusItem?.button?.image = Self.statusImage(badged: pending)
        statusItem?.button?.toolTip = pending ? String(localized: "MAC-LIMPO — update available") : nil
    }

    /// Clique na notificação de versão nova: abre o popover, onde está a faixa.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter, didReceive _: UNNotificationResponse
    ) async {
        await MainActor.run {
            if !self.popover.isShown { self.togglePopover() }
        }
    }

    /// Mostra a notificação mesmo com o app "em primeiro plano" (um app de
    /// barra de menus quase sempre está).
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter, willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    @objc func togglePopover() {
        closeWelcome()
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

    private func fill(_ rep: NSBitmapImageRep, from metal: MetalSnapshotting, in root: NSView) {
        guard let image = metal.snapshotImage(), let data = rep.bitmapData, rep.samplesPerPixel >= 3 else { return }
        let scale = CGFloat(rep.pixelsWide) / root.bounds.width
        var frame = metal.convert(metal.bounds, to: root)
        if !root.isFlipped { frame.origin.y = root.bounds.height - frame.maxY }
        let (left, top) = (Int(frame.minX * scale), Int(frame.minY * scale))
        let (width, height) = (min(image.width, rep.pixelsWide - left), min(image.height, rep.pixelsHigh - top))
        guard width > 0, height > 0 else { return }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let background = metal.snapshotBackground
        let target = [UInt8(background.r * 255), UInt8(background.g * 255), UInt8(background.b * 255)]
        for y in 0 ..< height {
            for x in 0 ..< width {
                let pixel = data + (top + y) * rep.bytesPerRow + (left + x) * rep.samplesPerPixel
                guard abs(Int(pixel[0]) - Int(target[0])) <= 3, abs(Int(pixel[1]) - Int(target[1])) <= 3,
                      abs(Int(pixel[2]) - Int(target[2])) <= 3 else { continue }
                let source = (y * image.width + x) * 4
                pixel[0] = pixels[source]
                pixel[1] = pixels[source + 1]
                pixel[2] = pixels[source + 2]
            }
        }
    }

    private func snapshotDiskXRay(to path: String) {
        // A moldura (superview do conteúdo) inclui a barra de título e a toolbar.
        guard let content = diskXRayWindow?.contentView,
              case let view = content.superview ?? content,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        // O `cacheDisplay` não enxerga camadas Metal (mapa 3D): onde a captura
        // ficou com a cor de fundo do mapa, entra a mesma imagem desenhada fora da
        // tela — o que está por cima (bandeiras, contornos) fica.
        func compose(_ node: NSView) {
            if let metal = node as? MetalSnapshotting { fill(rep, from: metal, in: view) }
            node.subviews.forEach(compose)
        }
        compose(view)
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

        window.title = String(localized: "Disk X-Ray — MAC-LIMPO")
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
