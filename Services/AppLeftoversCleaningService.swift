import AppKit
import Foundation

/// Service to clean leftovers from uninstalled applications.
///
/// Os dados de um app (ajustes, sessões, SDKs) só saem quando três coisas
/// provam que ele foi embora: o app não aparece em lugar nenhum (bundle id no
/// LaunchServices ou o nome em /Applications e ~/Applications), a pasta ficou
/// 90 dias sem nenhuma modificação — nem lá dentro — e ela não guarda nenhum
/// app. E vão para a Lixeira, nunca apagados de vez. Antes bastava não existir
/// `/Applications/<nome exato>.app`: VS Code em ~/Applications ou IDEs do
/// JetBrains Toolbox perdiam os ajustes.
class AppLeftoversCleaningService: BaseCleaningService, CleaningService, @unchecked Sendable {
    let category: CleaningCategory = .appLeftovers

    struct Rule: Sendable {
        let name: String
        /// Pasta de dados do app (aceita `*` como glob).
        let path: String
        let bundleIDs: [String]
        let appNames: [String]
        /// Só no modo agressivo: grande e usado por outras ferramentas.
        var aggressive = false
    }

    static let maxIdleDays = 90

    private let knownApps = [
        Rule(
            name: "Cursor",
            path: "~/Library/Application Support/Cursor",
            bundleIDs: ["com.todesktop.230313mzl4w4u92"],
            appNames: ["Cursor.app"]
        ),
        Rule(name: "Trae", path: "~/Library/Application Support/Trae", bundleIDs: ["com.trae.app"], appNames: ["Trae.app"]),
        Rule(
            name: "VS Code",
            path: "~/Library/Application Support/Code",
            bundleIDs: ["com.microsoft.VSCode"],
            appNames: ["Visual Studio Code.app"]
        ),
        Rule(
            name: "Android Studio",
            path: "~/Library/Application Support/Google/AndroidStudio*",
            bundleIDs: ["com.google.android.studio"],
            appNames: ["Android Studio.app"]
        ),
        Rule(name: "Zoom", path: "~/Library/Application Support/zoom.us", bundleIDs: ["us.zoom.xos"], appNames: ["zoom.us.app"]),
        Rule(name: "Discord", path: "~/Library/Application Support/discord", bundleIDs: ["com.hnc.Discord"], appNames: ["Discord.app"]),
        Rule(
            name: "Slack",
            path: "~/Library/Application Support/Slack",
            bundleIDs: ["com.tinyspeck.slackmacgap"],
            appNames: ["Slack.app"]
        ),
        Rule(
            name: "Postman",
            path: "~/Library/Application Support/Postman",
            bundleIDs: ["com.postmanlabs.mac"],
            appNames: ["Postman.app"]
        ),
        Rule(
            name: "Docker",
            path: "~/Library/Application Support/Docker Desktop",
            bundleIDs: ["com.docker.docker"],
            appNames: ["Docker.app"]
        ),
        // O SDK também serve ao Flutter e ao React Native sem o Studio.
        Rule(
            name: "Android SDK",
            path: "~/Library/Android",
            bundleIDs: ["com.google.android.studio"],
            appNames: ["Android Studio.app"],
            aggressive: true
        ),
        Rule(
            name: "Visual Studio",
            path: "~/Library/Application Support/VisualStudio",
            bundleIDs: ["com.microsoft.visual-studio"],
            appNames: ["Visual Studio.app"]
        ),
        Rule(
            name: "Zed",
            path: "~/Library/Application Support/Zed",
            bundleIDs: ["dev.zed.Zed", "dev.zed.Zed-Preview"],
            appNames: ["Zed.app", "Zed Preview.app"]
        ),
        // Installer framework leftover from Wondershare Dr.Fone (only if app is gone)
        Rule(
            name: "Wondershare Dr.Fone",
            path: "~/Library/Application Support/com.wondershare.Installer",
            bundleIDs: [],
            appNames: ["Wondershare Dr.Fone.app"]
        ),
        // Versões antigas do Toolbox guardam as próprias IDEs aqui dentro — a
        // regra "não guarda app" protege essas.
        Rule(
            name: "JetBrains Toolbox",
            path: "~/Library/Application Support/JetBrains/Toolbox",
            bundleIDs: ["com.jetbrains.toolbox"],
            appNames: ["JetBrains Toolbox.app"]
        )
    ]

    /// Produto JetBrains (prefixo da pasta de ajustes) → bundle ids e nomes do
    /// app. O Toolbox instala com outros nomes ("IntelliJ IDEA Ultimate.app") e
    /// em ~/Applications; o bundle id resolve os dois casos.
    static let jetBrainsProducts: [String: (bundleIDs: [String], appNames: [String])] = [
        "IntelliJIdea": (["com.jetbrains.intellij"], ["IntelliJ IDEA.app", "IntelliJ IDEA Ultimate.app"]),
        "IdeaIC": (["com.jetbrains.intellij.ce"], ["IntelliJ IDEA CE.app", "IntelliJ IDEA Community Edition.app"]),
        "PyCharm": (["com.jetbrains.pycharm"], ["PyCharm.app", "PyCharm Professional Edition.app"]),
        "PyCharmCE": (["com.jetbrains.pycharm.ce"], ["PyCharm CE.app", "PyCharm Community Edition.app"]),
        "WebStorm": (["com.jetbrains.WebStorm"], ["WebStorm.app"]),
        "Rider": (["com.jetbrains.rider"], ["Rider.app"]),
        "GoLand": (["com.jetbrains.goland"], ["GoLand.app"]),
        "DataGrip": (["com.jetbrains.datagrip"], ["DataGrip.app"]),
        "RubyMine": (["com.jetbrains.rubymine"], ["RubyMine.app"]),
        "RustRover": (["com.jetbrains.rustrover"], ["RustRover.app"]),
        "CLion": (["com.jetbrains.CLion"], ["CLion.app"]),
        "PhpStorm": (["com.jetbrains.PhpStorm"], ["PhpStorm.app"]),
        "Aqua": (["com.jetbrains.aqua"], ["Aqua.app"])
    ]

    /// "PyCharmCE2024.3" → "PyCharmCE". `nil` para pastas sem versão
    /// (consentOptions, bl…), que nunca são tratadas como sobra. O produto é o
    /// nome inteiro antes da versão — por prefixo, "PyCharm" casava com o CE.
    static func jetBrainsProduct(ofFolder folder: String) -> String? {
        guard folder.range(of: #"^[A-Za-z]+\d{4}\.\d+$"#, options: .regularExpression) != nil else { return nil }
        return String(folder.prefix { $0.isLetter })
    }

    /// Regras das pastas de ajustes por versão em `jetBrainsRoot`.
    static func jetBrainsRules(in jetBrainsRoot: String) -> [Rule] {
        FileSystemHelper.shared.contentsOfDirectory(atPath: jetBrainsRoot).sorted().compactMap { folder in
            guard let product = jetBrainsProduct(ofFolder: folder), let app = jetBrainsProducts[product] else { return nil }
            return Rule(
                name: "JetBrains \(folder)",
                path: (jetBrainsRoot as NSString).appendingPathComponent(folder),
                bundleIDs: app.bundleIDs,
                appNames: app.appNames
            )
        }
    }

    /// Pastas de `rules` que são sobra de app desinstalado em `now`.
    static func leftovers(
        rules: [Rule],
        aggressiveMode: Bool,
        now: Date = Date(),
        isInstalled: (Rule) -> Bool = isAppInstalled
    ) -> [(rule: Rule, path: String)] {
        let helper = FileSystemHelper.shared
        let cutoff = now.addingTimeInterval(-Double(maxIdleDays) * 86400)
        var found: [(rule: Rule, path: String)] = []
        for rule in rules where aggressiveMode || !rule.aggressive {
            let paths = SystemDataCleaningService.expandGlob(helper.expandPath(rule.path))
                .filter { helper.fileExists(atPath: $0) }
                .sorted()
            // Barato primeiro: a varredura de datas e de apps só roda para quem sobrou.
            guard !paths.isEmpty, !isInstalled(rule) else { continue }
            for path in paths where !helper.hasModifications(since: cutoff, atPath: path) && !containsApplication(atPath: path) {
                found.append((rule, path))
            }
        }
        return found
    }

    /// O app está em algum lugar deste Mac?
    static func isAppInstalled(_ rule: Rule) -> Bool {
        if rule.bundleIDs.contains(where: { !NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0).isEmpty }) {
            return true
        }
        let home = NSHomeDirectory()
        let folders = [
            "/Applications",
            "/Applications/Setapp",
            "\(home)/Applications",
            "\(home)/Applications/JetBrains Toolbox"
        ]
        return rule.appNames.contains { name in
            folders.contains { FileManager.default.fileExists(atPath: ($0 as NSString).appendingPathComponent(name)) }
        }
    }

    /// Há um `.app` em `path` ou dentro dele? Uma pasta que guarda apps não é sobra.
    static func containsApplication(atPath path: String) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants]
        ) else { return false }
        while let child = enumerator.nextObject() as? URL {
            if child.pathExtension == "app" { return true }
        }
        return false
    }

    private var rules: [Rule] {
        knownApps + Self.jetBrainsRules(in: fileHelper.expandPath("~/Library/Application Support/JetBrains"))
    }

    func scan(progress: (@Sendable (String) -> Void)?) async -> ScanResult {
        Logger.shared.log("Scanning for app leftovers...", level: .info)
        progress?(String(localized: "Scanning \(category.displayName)…"))

        let found = Self.leftovers(rules: rules, aggressiveMode: CleaningOptions.shared.aggressiveMode)
        let sizes = await fileHelper.sizesOfDirectoriesAsync(atPaths: found.map(\.path))
        var totalSize: Int64 = 0
        var items: [String] = []
        for (rule, path) in found {
            let size = sizes[path] ?? 0
            totalSize += size
            items.append("\(rule.name) (Leftover): \(fileHelper.formatBytes(size))")
            Logger.shared.log("Found leftover: \(rule.name) at \(path)", level: .debug)
        }

        return ScanResult(
            category: category,
            estimatedSize: totalSize,
            itemCount: items.count,
            items: items
        )
    }

    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []

        for (rule, path) in Self.leftovers(rules: rules, aggressiveMode: CleaningOptions.shared.aggressiveMode) {
            let size = fileHelper.sizeOfDirectory(atPath: path)
            if fileHelper.trashItem(atPath: path) {
                bytesRemoved += size
                filesRemoved += 1
                Logger.shared.log("Leftover movido para a Lixeira: \(path)", level: .info)
            } else {
                errors.append(String(localized: "Could not move \(rule.name) to the Trash."))
            }
        }

        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: Date().timeIntervalSince(startTime),
            success: errors.isEmpty
        )
    }
}
