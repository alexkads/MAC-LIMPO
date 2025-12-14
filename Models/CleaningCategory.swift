import SwiftUI

enum CleaningCategory: String, CaseIterable, Identifiable {
    // Desenvolvimento
    case docker = "Docker"
    case devPackages = "Dev Packages"
    case xcodeCache = "Xcode Cache"
    case iosSimulators = "iOS Simulators"
    
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
    
    // Arquivos grandes e duplicados
    case largeFiles = "Large Files"
    case duplicateFiles = "Duplicate Files"
    
    // Email e Mensagens
    case mailAttachments = "Mail Attachments"
    case messagesAttachments = "Messages Attachments"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .docker: return "shippingbox.fill"
        case .devPackages: return "hammer.fill"
        case .xcodeCache: return "chevron.left.forwardslash.chevron.right"
        case .iosSimulators: return "iphone.gen3"
        case .tempFiles: return "doc.fill"
        case .logs: return "list.bullet.rectangle.fill"
        case .appCache: return "tray.full.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .trash: return "trash.fill"
        case .browserCache: return "network"
        case .spotifyCache: return "music.note"
        case .slackCache: return "bubble.left.and.bubble.right.fill"
        case .largeFiles: return "doc.badge.ellipsis"
        case .duplicateFiles: return "doc.on.doc.fill"
        case .mailAttachments: return "envelope.fill"
        case .messagesAttachments: return "message.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .docker: return Color(hex: "2196F3")
        case .devPackages: return Color(hex: "FF6F00")
        case .xcodeCache: return Color(hex: "147EFB")
        case .iosSimulators: return Color(hex: "5AC8FA")
        case .tempFiles: return Color(hex: "9C27B0")
        case .logs: return Color(hex: "00BCD4")
        case .appCache: return Color(hex: "4CAF50")
        case .downloads: return Color(hex: "FF9800")
        case .trash: return Color(hex: "F44336")
        case .browserCache: return Color(hex: "3F51B5")
        case .spotifyCache: return Color(hex: "1DB954")
        case .slackCache: return Color(hex: "4A154B")
        case .largeFiles: return Color(hex: "E91E63")
        case .duplicateFiles: return Color(hex: "9E9E9E")
        case .mailAttachments: return Color(hex: "2196F3")
        case .messagesAttachments: return Color(hex: "34C759")
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
        case .largeFiles:
            return "Find files larger than 500MB"
        case .duplicateFiles:
            return "Detect duplicate files to remove"
        case .mailAttachments:
            return "Clean old Mail app attachments"
        case .messagesAttachments:
            return "Remove old Messages attachments"
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
