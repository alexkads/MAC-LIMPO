// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MAC-LIMPO",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MAC-LIMPO",
            targets: ["MAC-LIMPO"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MAC-LIMPO",
            path: ".",
            exclude: [
                "README.md",
                "XCODE_SETUP.md",
                "CHANGELOG.md",
                "CONTRIBUTING.md",
                "docs",
                "Info.plist",
                "create_xcode_project.sh",
                "create_installer.sh",
                "Assets.xcassets",
                "Design",
                "MAC-LIMPO.app",
                "MAC-LIMPO.dmg",
                "Services/COMO_VER_LOGS.md",
                "Services/CORRECAO_APLICADA.md",
                "Services/CORRECAO_TEMPFILES.md",
                "Services/GUIA_INSTALACAO.md",
                "Services/IDEIAS_FUTURAS.md",
                "Services/NOVAS_CATEGORIAS.md",
                "Services/PROBLEMAS_E_CORRECOES.md",
                "Services/capture_errors.sh",
                "Services/check_files.sh",
                "Services/Logger 2.swift",
                "analyze_system_data.sh",
                "deep_analysis.sh"
            ],
            sources: [
                "MACLIMPOApp.swift",
                "Models/CleaningCategory.swift",
                "Models/CleaningResult.swift",
                "Models/FileNode.swift",
                "Services/CleaningService.swift",
                "Services/DockerCleaningService.swift",
                "Services/DevPackagesCleaningService.swift",
                "Services/TempFilesCleaningService.swift",
                "Services/LogsCleaningService.swift",
                "Services/AppCacheCleaningService.swift",
                "Services/LaunchAtLoginService.swift",
                "Services/Logger.swift",
                "Services/DiskMapService.swift",
                // Novos serviços de limpeza
                "Services/XcodeCacheCleaningService.swift",
                "Services/IOSSimulatorsCleaningService.swift",
                "Services/DownloadsCleaningService.swift",
                "Services/TrashCleaningService.swift",
                "Services/BrowserCacheCleaningService.swift",
                "Services/SpotifyCacheCleaningService.swift",
                "Services/SlackCacheCleaningService.swift",
                "Services/AdobeCleaningService.swift",
                "Services/MailAttachmentsCleaningService.swift",
                "Services/MessagesAttachmentsCleaningService.swift",
                // Serviços para limpeza adicional de espaço
                "Services/IDECacheCleaningService.swift",
                "Services/AndroidSDKCleaningService.swift",
                "Services/MessagingAppsCleaningService.swift",
                "Services/PlaywrightCleaningService.swift",
                "Services/CargoCleaningService.swift",
                "Services/HomebrewCleaningService.swift",
                "Services/TerminalLogsCleaningService.swift",
                "Services/SystemDataCleaningService.swift",
                // ViewModels
                "ViewModels/TreemapViewModel.swift",
                // Views
                "Views/MenuBarView.swift",
                "Views/TreemapView.swift",
                "Views/TreemapWindowView.swift",
                "Views/Components/CleaningCategoryCard.swift",
                "Views/Components/StorageStatsView.swift",
                "Views/Components/CleaningProgressView.swift",
                "Views/Components/ResultsView.swift",
                "Views/Components/DirectoryCard.swift",
                // Utilities
                "Utilities/FileSystemHelper.swift",
                "Utilities/ShellExecutor.swift",
                "Utilities/TreemapLayout.swift",
                "Utilities/PermissionsHelper.swift"
            ]
        )
    ]
)
