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
    
    var group: CleaningGroup {
        switch self {
        case .docker, .xcodeCache, .devPackages, .ideCache, .androidSDK, .playwright, .cargo, .homebrew, .terminalLogs, .aiTools, .iosSimulators:
            return .development
        case .systemData, .tempFiles, .logs, .trash, .varFolders:
            return .system
        case .appCache, .browserCache, .adobeCache, .downloads, .creativeApps:
            return .apps
        case .slackCache, .messagingApps, .mailAttachments, .messagesAttachments:
            return .communication
        case .spotifyCache, .podcasts:
            return .media
        }
    }
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .docker: return "shippingbox.fill"
        case .devPackages: return "hammer.fill"
        case .xcodeCache: return "chevron.left.forwardslash.chevron.right"
        case .iosSimulators: return "iphone.gen3"
        case .ideCache: return "laptopcomputer"
        case .androidSDK: return "apps.iphone"
        case .playwright: return "theatermasks.fill"
        case .cargo: return "shippingbox"
        case .homebrew: return "mug.fill"
        case .terminalLogs: return "terminal.fill"
        case .tempFiles: return "doc.fill"
        case .logs: return "list.bullet.rectangle.fill"
        case .appCache: return "tray.full.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .trash: return "trash.fill"
        case .browserCache: return "network"
        case .spotifyCache: return "music.note"
        case .slackCache: return "bubble.left.and.bubble.right.fill"
        case .messagingApps: return "bubble.left.and.text.bubble.right.fill"
        case .adobeCache: return "paintbrush.fill"
        case .mailAttachments: return "envelope.fill"
        case .messagesAttachments: return "message.fill"
        case .systemData: return "internaldrive.fill"
        case .varFolders: return "folder.fill"
        case .aiTools: return "brain.head.profile"
        case .creativeApps: return "paintpalette.fill"
        case .podcasts: return "mic.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .docker: return Color(hex: "2196F3")
        case .devPackages: return Color(hex: "FF6F00")
        case .xcodeCache: return Color(hex: "147EFB")
        case .iosSimulators: return Color(hex: "5AC8FA")
        case .ideCache: return Color(hex: "007ACC")
        case .androidSDK: return Color(hex: "3DDC84")
        case .playwright: return Color(hex: "2EAD33")
        case .cargo: return Color(hex: "FF6B35")
        case .homebrew: return Color(hex: "FBB040")
        case .terminalLogs: return Color(hex: "00C9A7")
        case .tempFiles: return Color(hex: "9C27B0")
        case .logs: return Color(hex: "00BCD4")
        case .appCache: return Color(hex: "4CAF50")
        case .downloads: return Color(hex: "FF9800")
        case .trash: return Color(hex: "F44336")
        case .browserCache: return Color(hex: "3F51B5")
        case .spotifyCache: return Color(hex: "1DB954")
        case .slackCache: return Color(hex: "4A154B")
        case .messagingApps: return Color(hex: "25D366")
        case .adobeCache: return Color(hex: "FF0000")
        case .mailAttachments: return Color(hex: "2196F3")
        case .messagesAttachments: return Color(hex: "34C759")
        case .systemData: return Color(hex: "8E44AD")
        case .varFolders: return Color(hex: "E67E22")
        case .aiTools: return Color(hex: "9B59B6")
        case .creativeApps: return Color(hex: "E91E63")
        case .podcasts: return Color(hex: "673AB7")
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
            return "Remove unused containers, images, and volumes"
        case .devPackages:
            return "Clear npm, pip, brew, and cargo caches"
        case .xcodeCache:
            return "Clean DerivedData, Archives, and build caches"
        case .iosSimulators:
            return "Remove old iOS Simulator devices and data"
        case .ideCache:
            return "Clean JetBrains, VS Code, Cursor caches"
        case .androidSDK:
            return "Clean Gradle cache and old Android SDK data"
        case .playwright:
            return "Remove Playwright browser caches"
        case .cargo:
            return "Clean Rust/Cargo build cache and registry"
        case .homebrew:
            return "Clear Homebrew package download cache"
        case .terminalLogs:
            return "Remove old terminal log files"
        case .tempFiles:
            return "Delete temporary files and caches"
        case .logs:
            return "Clean up old system and app logs (30+ days)"
        case .appCache:
            return "Clear application caches"
        case .downloads:
            return "Remove downloads older than 30 days"
        case .trash:
            return "Empty Trash and recover space"
        case .browserCache:
            return "Clear Safari, Chrome, Firefox cache"
        case .spotifyCache:
            return "Clean Spotify offline cache"
        case .slackCache:
            return "Clear Slack cache and temp files"
        case .messagingApps:
            return "Clean WhatsApp, Teams, Discord caches"
        case .adobeCache:
            return "Clear Adobe apps cache and media files"
        case .mailAttachments:
            return "Clean old Mail app attachments"
        case .messagesAttachments:
            return "Remove old Messages attachments"
        case .systemData:
            return "Deep clean system caches and temporary data"
        case .varFolders:
            return "Clean /var/folders temp caches (Chrome, Metal, clang)"
        case .aiTools:
            return "Clear AI tools cache (Claude, Gemini, Cursor, Copilot)"
        case .creativeApps:
            return "Clean Canva, Affinity, Figma caches"
        case .podcasts:
            return "Remove downloaded episodes and caches"
        }
    }
}

enum CleaningGroup: String, CaseIterable, Identifiable {
    case development = "Development"
    case system = "System"
    case apps = "Apps & Browsers"
    case communication = "Communication"
    case media = "Media"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .development: return "hammer.fill"
        case .system: return "gear"
        case .apps: return "app.badge.fill"
        case .communication: return "bubble.left.and.bubble.right.fill"
        case .media: return "play.circle.fill"
        }
    }
}

// Extension para criar cores de hex
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
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
