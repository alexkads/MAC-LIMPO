import SwiftUI

enum CleaningCategory: String, CaseIterable, Identifiable {
    // Desenvolvimento
    case docker = "Docker"
    case devPackages = "Dev Packages"
    case xcodeCache = "Xcode Cache"
    case iosSimulators = "iOS Simulators"
    case ideCache = "IDE Cache"
    case androidSDK = "Android SDK"
    case playwright = "Playwright"
    case cargo = "Cargo/Rust"
    case homebrew = "Homebrew"
    case terminalLogs = "Terminal Logs"

    // Sistema
    case tempFiles = "Temp Files"
    case logs = "Logs"
    case appCache = "App Cache"
    case downloads = "Old Downloads"
    case trash = "Trash Bin"

    // Navegadores e Apps
    case browserCache = "Browser Cache"
    case spotifyCache = "Spotify Cache"
    case slackCache = "Slack Cache"
    case messagingApps = "Messaging Apps"
    case adobeCache = "Adobe Cache"

    // Email e Mensagens
    case mailAttachments = "Mail Attachments"
    case messagesAttachments = "Messages Attachments"

    // System Deep Clean
    case systemData = "System Data"
    case varFolders = "Var Folders"
    case aiTools = "AI Tools"
    case creativeApps = "Creative Apps"
    case podcasts = "Podcasts"
    case appLeftovers = "App Leftovers"
    case development = "Project Builds"

    // Novos serviços
    case pnpm = "pnpm Store"
    case goCache = "Go Cache"
    case devApiTools = "API Tools"
    case notionCache = "Notion Cache"
    case cypress = "Cypress"
    case tiktokLiveStudio = "TikTok LIVE Studio"

    var group: CleaningGroup {
        switch self {
        case .docker, .xcodeCache, .devPackages, .ideCache, .androidSDK, .playwright, .cargo, .homebrew, .terminalLogs,
             .aiTools, .iosSimulators, .pnpm, .goCache, .devApiTools, .cypress:
            .development
        case .systemData, .tempFiles, .logs, .trash, .varFolders, .appLeftovers:
            .system
        case .development:
            .development
        case .appCache, .browserCache, .adobeCache, .downloads, .creativeApps, .notionCache:
            .apps
        case .slackCache, .messagingApps, .mailAttachments, .messagesAttachments:
            .communication
        case .spotifyCache, .podcasts, .tiktokLiveStudio:
            .media
        }
    }

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .docker: "shippingbox.fill"
        case .devPackages: "hammer.fill"
        case .xcodeCache: "chevron.left.forwardslash.chevron.right"
        case .iosSimulators: "iphone.gen3"
        case .ideCache: "laptopcomputer"
        case .androidSDK: "apps.iphone"
        case .playwright: "theatermasks.fill"
        case .cargo: "shippingbox"
        case .homebrew: "mug.fill"
        case .terminalLogs: "terminal.fill"
        case .tempFiles: "doc.fill"
        case .logs: "list.bullet.rectangle.fill"
        case .appCache: "tray.full.fill"
        case .downloads: "arrow.down.circle.fill"
        case .trash: "trash.fill"
        case .browserCache: "network"
        case .spotifyCache: "music.note"
        case .slackCache: "bubble.left.and.bubble.right.fill"
        case .messagingApps: "bubble.left.and.text.bubble.right.fill"
        case .adobeCache: "paintbrush.fill"
        case .mailAttachments: "envelope.fill"
        case .messagesAttachments: "message.fill"
        case .systemData: "internaldrive.fill"
        case .varFolders: "folder.fill"
        case .aiTools: "brain.head.profile"
        case .creativeApps: "paintpalette.fill"
        case .podcasts: "mic.fill"
        case .appLeftovers: "exclamationmark.triangle.fill"
        case .development: "hammer.fill"
        case .pnpm: "shippingbox.and.arrow.backward.fill"
        case .goCache: "hare.fill"
        case .devApiTools: "network.badge.shield.half.filled"
        case .notionCache: "doc.richtext.fill"
        case .cypress: "checkmark.shield.fill"
        case .tiktokLiveStudio: "dot.radiowaves.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .docker: Color(hex: "2196F3")
        case .devPackages: Color(hex: "FF6F00")
        case .xcodeCache: Color(hex: "147EFB")
        case .iosSimulators: Color(hex: "5AC8FA")
        case .ideCache: Color(hex: "007ACC")
        case .androidSDK: Color(hex: "3DDC84")
        case .playwright: Color(hex: "2EAD33")
        case .cargo: Color(hex: "FF6B35")
        case .homebrew: Color(hex: "FBB040")
        case .terminalLogs: Color(hex: "00C9A7")
        case .tempFiles: Color(hex: "9C27B0")
        case .logs: Color(hex: "00BCD4")
        case .appCache: Color(hex: "4CAF50")
        case .downloads: Color(hex: "FF9800")
        case .trash: Color(hex: "F44336")
        case .browserCache: Color(hex: "3F51B5")
        case .spotifyCache: Color(hex: "1DB954")
        case .slackCache: Color(hex: "4A154B")
        case .messagingApps: Color(hex: "25D366")
        case .adobeCache: Color(hex: "FF0000")
        case .mailAttachments: Color(hex: "2196F3")
        case .messagesAttachments: Color(hex: "34C759")
        case .systemData: Color(hex: "8E44AD")
        case .varFolders: Color(hex: "E67E22")
        case .aiTools: Color(hex: "9B59B6")
        case .creativeApps: Color(hex: "E91E63")
        case .podcasts: Color(hex: "673AB7")
        case .appLeftovers: Color(hex: "C0392B") // Red for leftovers
        case .development: Color(hex: "E67E22")
        case .pnpm: Color(hex: "F9A825") // pnpm orange/gold
        case .goCache: Color(hex: "00ACD7") // Go cyan
        case .devApiTools: Color(hex: "FF6C37") // Postman orange
        case .notionCache: Color(hex: "37352F") // Notion dark
        case .cypress: Color(hex: "04C38E") // Cypress teal
        case .tiktokLiveStudio: Color(hex: "FE2C55") // TikTok red/pink
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [color, color.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var description: String {
        switch self {
        case .docker:
            "Remove unused containers, images, and volumes"
        case .devPackages:
            "Clear npm, pip, brew, and cargo caches"
        case .xcodeCache:
            "Clean DerivedData, Archives, and build caches"
        case .iosSimulators:
            "Remove old iOS Simulator devices and data"
        case .ideCache:
            "Clean JetBrains, VS Code, Cursor caches"
        case .androidSDK:
            "Clean Gradle cache and old Android SDK data"
        case .playwright:
            "Remove Playwright browser caches"
        case .cargo:
            "Clean Rust/Cargo build cache and registry"
        case .homebrew:
            "Clear Homebrew package download cache"
        case .terminalLogs:
            "Remove old terminal log files"
        case .tempFiles:
            "Delete temporary files and caches"
        case .logs:
            "Clean up old system and app logs (30+ days)"
        case .appCache:
            "Clear application caches"
        case .downloads:
            "Remove downloads older than 30 days"
        case .trash:
            "Empty Trash and recover space"
        case .browserCache:
            "Clear Safari, Chrome, Firefox cache"
        case .spotifyCache:
            "Clean Spotify offline cache"
        case .slackCache:
            "Clear Slack cache and temp files"
        case .messagingApps:
            "Clean WhatsApp, Teams, Discord caches"
        case .adobeCache:
            "Clear Adobe apps cache and media files"
        case .mailAttachments:
            "Clean old Mail app attachments"
        case .messagesAttachments:
            "Remove old Messages attachments"
        case .systemData:
            "Deep clean system caches and temporary data"
        case .varFolders:
            "Clean /var/folders temp caches (Chrome, Metal, clang)"
        case .aiTools:
            "Clear AI tools cache (Claude, Gemini, Cursor, Copilot)"
        case .creativeApps:
            "Clean Canva, Affinity, Figma caches"
        case .podcasts:
            "Remove downloaded episodes and caches"
        case .appLeftovers:
            "Remove data from uninstalled apps (JetBrains, Trae, etc)"
        case .development:
            "Clean node_modules, Rust targets, and build artifacts"
        case .pnpm:
            "Clean pnpm package store and dlx/metadata caches"
        case .goCache:
            "Clean Go module cache, build cache, and gopls"
        case .devApiTools:
            "Clean Postman, Insomnia, Bruno caches and logs"
        case .notionCache:
            "Remove Notion asset cache and GPU caches"
        case .cypress:
            "Clean Cypress test data and browser binary cache"
        case .tiktokLiveStudio:
            "Clean TikTok LIVE Studio browser cache and logs (keeps your effects/assets)"
        }
    }
}

enum CleaningGroup: String, CaseIterable, Identifiable {
    case development = "Development"
    case system = "System"
    case apps = "Apps & Browsers"
    case communication = "Communication"
    case media = "Media"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .development: "hammer.fill"
        case .system: "gear"
        case .apps: "app.badge.fill"
        case .communication: "bubble.left.and.bubble.right.fill"
        case .media: "play.circle.fill"
        }
    }
}

/// Extension para criar cores de hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
