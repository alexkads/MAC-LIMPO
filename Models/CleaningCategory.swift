import SwiftUI

enum CleaningCategory: String, CaseIterable, Identifiable, Sendable {
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
    case rustTargets = "Rust Targets"

    // Novos serviços
    case pnpm = "pnpm Store"
    case goCache = "Go Cache"
    case devApiTools = "API Tools"
    case notionCache = "Notion Cache"
    case cypress = "Cypress"
    case tiktokLiveStudio = "TikTok LIVE Studio"
    case nugetCache = "NuGet Cache"
    case bunCache = "Bun Cache"
    case pubCache = "pub Cache"
    case googleCache = "Google Cache"

    // Dev tooling e IA
    case nvmVersions = "Node Versions"
    case azureTools = "Azure Tools"
    case expoCache = "Expo Cache"
    case zedCache = "Zed Cache"
    case aiModels = "AI Models"
    case dotnetSdks = ".NET SDKs"

    var group: CleaningGroup {
        switch self {
        case .docker, .xcodeCache, .devPackages, .ideCache, .androidSDK, .playwright, .cargo, .homebrew, .terminalLogs,
             .aiTools, .iosSimulators, .pnpm, .goCache, .devApiTools, .cypress,
             .nugetCache, .bunCache, .pubCache,
             .nvmVersions, .azureTools, .expoCache, .zedCache, .aiModels, .dotnetSdks:
            .development
        case .systemData, .tempFiles, .logs, .trash, .varFolders, .appLeftovers:
            .system
        case .development, .rustTargets:
            .development
        case .appCache, .browserCache, .adobeCache, .downloads, .creativeApps, .notionCache, .googleCache:
            .apps
        case .slackCache, .messagingApps, .mailAttachments, .messagesAttachments:
            .communication
        case .spotifyCache, .podcasts, .tiktokLiveStudio:
            .media
        }
    }

    /// Nome na interface, traduzido. O rawValue fica como identidade estável
    /// (id do ForEach, logs) e não deve aparecer na tela.
    var displayName: String {
        switch self {
        case .docker: String(localized: "Docker")
        case .devPackages: String(localized: "Dev Packages")
        case .xcodeCache: String(localized: "Xcode Cache")
        case .iosSimulators: String(localized: "iOS Simulators")
        case .ideCache: String(localized: "IDE Cache")
        case .androidSDK: String(localized: "Android SDK")
        case .playwright: String(localized: "Playwright")
        case .cargo: String(localized: "Cargo/Rust")
        case .homebrew: String(localized: "Homebrew")
        case .terminalLogs: String(localized: "Terminal Logs")
        case .tempFiles: String(localized: "Temp Files")
        case .logs: String(localized: "Logs")
        case .appCache: String(localized: "App Cache")
        case .downloads: String(localized: "Old Downloads")
        case .trash: String(localized: "Trash Bin")
        case .browserCache: String(localized: "Browser Cache")
        case .spotifyCache: String(localized: "Spotify Cache")
        case .slackCache: String(localized: "Slack Cache")
        case .messagingApps: String(localized: "Messaging Apps")
        case .adobeCache: String(localized: "Adobe Cache")
        case .mailAttachments: String(localized: "Mail Attachments")
        case .messagesAttachments: String(localized: "Messages Attachments")
        case .systemData: String(localized: "System Data")
        case .varFolders: String(localized: "Var Folders")
        case .aiTools: String(localized: "AI Tools")
        case .creativeApps: String(localized: "Creative Apps")
        case .podcasts: String(localized: "Podcasts")
        case .appLeftovers: String(localized: "App Leftovers")
        case .development: String(localized: "Project Builds")
        case .rustTargets: String(localized: "Rust Targets")
        case .pnpm: String(localized: "pnpm Store")
        case .goCache: String(localized: "Go Cache")
        case .devApiTools: String(localized: "API Tools")
        case .notionCache: String(localized: "Notion Cache")
        case .cypress: String(localized: "Cypress")
        case .tiktokLiveStudio: String(localized: "TikTok LIVE Studio")
        case .nugetCache: String(localized: "NuGet Cache")
        case .bunCache: String(localized: "Bun Cache")
        case .pubCache: String(localized: "pub Cache")
        case .googleCache: String(localized: "Google Cache")
        case .nvmVersions: String(localized: "Node Versions")
        case .azureTools: String(localized: "Azure Tools")
        case .expoCache: String(localized: "Expo Cache")
        case .zedCache: String(localized: "Zed Cache")
        case .aiModels: String(localized: "AI Models")
        case .dotnetSdks: String(localized: ".NET SDKs")
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
        case .rustTargets: "cube.transparent"
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
        case .nugetCache: "cube.box.fill"
        case .bunCache: "takeoutbag.and.cup.and.straw.fill"
        case .pubCache: "bird.fill"
        case .googleCache: "globe"
        case .nvmVersions: "hexagon.fill"
        case .azureTools: "cloud.fill"
        case .expoCache: "atom"
        case .zedCache: "bolt.fill"
        case .aiModels: "cpu.fill"
        case .dotnetSdks: "square.stack.3d.up.fill"
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
        case .rustTargets: Color(hex: "CE422B")
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
        case .nugetCache: Color(hex: "004880") // NuGet blue
        case .bunCache: Color(hex: "F472B6") // Bun pink
        case .pubCache: Color(hex: "0175C2") // Dart blue
        case .googleCache: Color(hex: "4285F4") // Google blue
        case .nvmVersions: Color(hex: "339933") // Node green
        case .azureTools: Color(hex: "0078D4") // Azure blue
        case .expoCache: Color(hex: "4630EB") // Expo indigo
        case .zedCache: Color(hex: "084CCF") // Zed blue
        case .aiModels: Color(hex: "5856D6") // System indigo
        case .dotnetSdks: Color(hex: "512BD4") // .NET purple
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
            String(localized: "Remove unused containers, images, and volumes")
        case .devPackages:
            String(localized: "Clear npm, pip, brew, and cargo caches")
        case .xcodeCache:
            String(localized: "Clean DerivedData, Archives, and build caches")
        case .iosSimulators:
            String(localized: "Remove old iOS Simulator devices and data")
        case .ideCache:
            String(localized: "Clean JetBrains, VS Code, Cursor caches")
        case .androidSDK:
            String(localized: "Clean Gradle cache and old Android SDK data")
        case .playwright:
            String(localized: "Remove Playwright browser caches")
        case .cargo:
            String(localized: "Clean Rust/Cargo build cache and registry")
        case .homebrew:
            String(localized: "Clear Homebrew package download cache")
        case .terminalLogs:
            String(localized: "Remove old terminal log files")
        case .tempFiles:
            String(localized: "Delete temporary files and caches")
        case .logs:
            String(localized: "Clean up old system and app logs (30+ days)")
        case .appCache:
            String(localized: "Clear application caches")
        case .downloads:
            String(localized: "Remove downloads older than 30 days")
        case .trash:
            String(localized: "Empty Trash and recover space")
        case .browserCache:
            String(localized: "Clear Safari, Chrome, Firefox cache")
        case .spotifyCache:
            String(localized: "Clean Spotify offline cache")
        case .slackCache:
            String(localized: "Clear Slack cache and temp files")
        case .messagingApps:
            String(localized: "Clean WhatsApp, Teams, Discord caches")
        case .adobeCache:
            String(localized: "Clear Adobe apps cache and media files")
        case .mailAttachments:
            String(localized: "Clean old Mail app attachments")
        case .messagesAttachments:
            String(localized: "Remove old Messages attachments")
        case .systemData:
            String(localized: "Deep clean system caches and temporary data")
        case .varFolders:
            String(localized: "Clean /var/folders temp caches (Chrome, Metal, clang)")
        case .aiTools:
            String(localized: "Clear AI tools cache (Claude, Gemini, Cursor, Copilot)")
        case .creativeApps:
            String(localized: "Clean Canva, Affinity, Figma caches")
        case .podcasts:
            String(localized: "Remove downloaded episodes and caches")
        case .appLeftovers:
            String(localized: "Remove data from uninstalled apps (JetBrains, Trae, etc)")
        case .development:
            String(localized: "Clean node_modules and build artifacts from projects")
        case .rustTargets:
            String(localized: "Remove Cargo target/ build directories from Rust projects")
        case .pnpm:
            String(localized: "Clean pnpm package store and dlx/metadata caches")
        case .goCache:
            String(localized: "Clean Go module cache, build cache, and gopls")
        case .devApiTools:
            String(localized: "Clean Postman, Insomnia, Bruno caches and logs")
        case .notionCache:
            String(localized: "Remove Notion asset cache and GPU caches")
        case .cypress:
            String(localized: "Clean Cypress test data and browser binary cache")
        case .tiktokLiveStudio:
            String(localized: "Clean TikTok LIVE Studio browser cache and logs (keeps your effects/assets)")
        case .nugetCache:
            String(localized: "Clear the global NuGet package cache (restored on dotnet build)")
        case .bunCache:
            String(localized: "Clear Bun's global install cache")
        case .pubCache:
            String(localized: "Clear downloaded Dart/Flutter pub packages (re-fetched on pub get)")
        case .googleCache:
            String(localized: "Clear Chrome regenerable profile caches and old Google Updater versions")
        case .nvmVersions:
            String(localized: "Remove old nvm Node versions (keeps default and newest per major)")
        case .azureTools:
            String(localized: "Remove downloaded Azure Functions Core Tools versions")
        case .expoCache:
            String(localized: "Clear Expo Go, APK, and simulator app caches")
        case .zedCache:
            String(localized: "Remove Zed's downloaded runtimes, language servers, and logs")
        case .aiModels:
            String(localized: "Remove local AI model caches (Ollama/LM Studio models need aggressive mode)")
        case .dotnetSdks:
            String(localized: "Remove superseded .NET SDK and runtime patches (keeps newest of each line; asks admin password)")
        }
    }
}

enum CleaningGroup: String, CaseIterable, Identifiable {
    case development = "Development"
    case system = "System"
    case apps = "Apps & Browsers"
    case communication = "Communication"
    case media = "Media"

    /// Nome do grupo na interface, traduzido.
    var title: String {
        switch self {
        case .development: String(localized: "Development")
        case .system: String(localized: "System")
        case .apps: String(localized: "Apps & Browsers")
        case .communication: String(localized: "Communication")
        case .media: String(localized: "Media")
        }
    }

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
