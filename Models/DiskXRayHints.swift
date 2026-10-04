import Foundation

/// O que o Raio-X sabe dizer sobre um caminho: o que é e quem limpa.
struct XRayHint: Sendable, Equatable {
    enum Tone: Sendable {
        /// Um card do MAC-LIMPO limpa isto.
        case cleanable
        /// Só se resolve fora do app (Xcode, Docker Desktop, Finder…).
        case manual
        /// Informativo: não é lixo, ou não é espaço real.
        case info
    }

    let label: String
    let note: String?
    let category: CleaningCategory?
    let tone: Tone
}

enum XRayHints {
    /// Dicas escritas à mão para o que os services não descrevem sozinhos.
    /// Chave: caminho visível (com `~`), comparado por igualdade.
    private static let manual: [String: XRayHint] = [
        "~/Library/Containers/com.docker.docker": XRayHint(
            label: "Docker disk image",
            note: "Docker.raw holds every image, container and volume. It only shrinks after Docker Desktop compacts it.",
            category: .docker, tone: .cleanable
        ),
        "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime": XRayHint(
            label: "iOS Simulator runtimes",
            note: "Remove unused runtimes in Xcode ▸ Settings ▸ Components. `simctl runtime delete` alone may leave the file.",
            category: .iosSimulators, tone: .manual
        ),
        "/Library/Developer/CoreSimulator": XRayHint(
            label: "Simulator runtimes and caches",
            note: "Mounted runtime images are skipped here; their files live in AssetsV2.",
            category: .iosSimulators, tone: .manual
        ),
        "~/Library/Developer/CoreSimulator": XRayHint(
            label: "Simulator devices", note: nil, category: .iosSimulators, tone: .cleanable
        ),
        "~/Library/Developer/CoreDevice": XRayHint(
            label: "Connected device files",
            note: "DeviceFS is a virtual mount of your iPhone/iPad. It takes no space on this Mac and is not counted.",
            category: nil, tone: .info
        ),
        "~/Library/Developer/Xcode/DerivedData": XRayHint(
            label: "Xcode build data", note: nil, category: .xcodeCache, tone: .cleanable
        ),
        "~/Library/Developer/Xcode/iOS DeviceSupport": XRayHint(
            label: "Xcode device symbols", note: nil, category: .xcodeCache, tone: .cleanable
        ),
        "~/Library/Developer/Xcode/Archives": XRayHint(
            label: "Xcode archives",
            note: "Builds you archived for distribution. Delete old ones in Xcode ▸ Organizer.",
            category: nil, tone: .manual
        ),
        "~/Library/Caches": XRayHint(
            label: "App caches", note: nil, category: .appCache, tone: .cleanable
        ),
        "~/Library/Logs": XRayHint(label: "Logs", note: nil, category: .logs, tone: .cleanable),
        "~/.Trash": XRayHint(label: "Trash", note: nil, category: .trash, tone: .cleanable),
        "~/Downloads": XRayHint(label: "Downloads", note: nil, category: .downloads, tone: .cleanable),
        "~/Library/Android": XRayHint(label: "Android SDK", note: nil, category: .androidSDK, tone: .cleanable),
        "~/.rustup": XRayHint(label: "Rust toolchains", note: nil, category: .cargo, tone: .cleanable),
        "~/.cargo": XRayHint(label: "Cargo registry", note: nil, category: .cargo, tone: .cleanable),
        "~/.nvm": XRayHint(label: "Node versions (nvm)", note: nil, category: .nvmVersions, tone: .cleanable),
        "/opt/homebrew": XRayHint(
            label: "Homebrew packages",
            note: "Installed formulae and casks. `brew autoremove` drops unused dependencies.",
            category: .homebrew, tone: .manual
        ),
        "~/Library/Application Support/MobileSync/Backup": XRayHint(
            label: "iPhone/iPad backups",
            note: "Delete old backups in Finder ▸ your device ▸ Manage Backups.",
            category: nil, tone: .manual
        ),
        "~/Library/Mobile Documents": XRayHint(
            label: "iCloud Drive (local copies)",
            note: "Files kept on this Mac. \"Remove Download\" in Finder frees space and keeps them in iCloud.",
            category: nil, tone: .manual
        ),
        "~/Library/Mail": XRayHint(label: "Mail", note: nil, category: .mailAttachments, tone: .cleanable),
        "~/Library/Messages": XRayHint(
            label: "Messages", note: nil, category: .messagesAttachments, tone: .cleanable
        ),
        "~/Pictures/Photos Library.photoslibrary": XRayHint(
            label: "Photos library",
            note: "Turn on Photos ▸ Settings ▸ iCloud ▸ Optimize Mac Storage to keep originals in iCloud.",
            category: nil, tone: .manual
        ),
        "/Applications": XRayHint(
            label: "Applications",
            note: "Uninstall apps you no longer use; App Leftovers cleans what they leave behind.",
            category: nil, tone: .info
        ),
        "/private/var/folders": XRayHint(
            label: "Per-user temporary files", note: nil, category: .varFolders, tone: .cleanable
        ),
        "/private/var/db": XRayHint(
            label: "System databases", note: "Spotlight, launch services, diagnostics. Managed by macOS.",
            category: nil, tone: .info
        ),
        "/Library/Application Support/Apple": XRayHint(
            label: "Apple system assets", note: "Managed by macOS.", category: nil, tone: .info
        )
    ]

    /// Dicas derivadas dos alvos dos services path-based, para o Raio-X e a
    /// limpeza nunca discordarem sobre quem limpa o quê. Globs ficam de fora.
    @MainActor
    private static let fromServices: [String: XRayHint] = {
        var hints: [String: XRayHint] = [:]
        for (category, service) in CleaningServiceRegistry.shared.services {
            guard let pathBased = service as? PathBasedCleaningService else { continue }
            for target in pathBased.targets where !target.path.contains("*") {
                hints[target.path] = XRayHint(
                    label: target.label ?? category.rawValue,
                    note: nil, category: category, tone: .cleanable
                )
            }
        }
        return hints
    }()

    /// Dica para um caminho visível (ex.: "/Users/x/Library/Caches").
    @MainActor
    static func hint(forDisplayPath path: String, home: String = NSHomeDirectory()) -> XRayHint? {
        let key = path == home ? "~" : (path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
        return manual[key] ?? fromServices[key]
    }

    /// Só o que está na home do usuário, e nunca as pastas-base dela
    /// (Library, Documents…), pode ir para a Lixeira pelo Raio-X.
    static func canTrash(displayPath path: String, home: String = NSHomeDirectory()) -> Bool {
        guard path.hasPrefix(home + "/") else { return false }
        let relative = path.dropFirst(home.count + 1)
        let components = relative.split(separator: "/")
        guard let first = components.first else { return false }
        if components.count == 1 { return !protectedHomeFolders.contains(String(first)) }
        // Dentro da Library só abaixo de Caches/Application Support/Containers…
        // nunca a Library em si nem seus filhos diretos.
        if first == "Library" { return components.count >= 3 }
        return true
    }

    private static let protectedHomeFolders: Set<String> = [
        "Library", "Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies",
        "Public", "Applications", ".Trash", "Sites"
    ]
}
