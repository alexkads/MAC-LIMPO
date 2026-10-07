// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MAC-LIMPO",
    platforms: [
        .macOS("26.6")
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
                "CLAUDE.md",
                "XCODE_SETUP.md",
                "CHANGELOG.md",
                "CONTRIBUTING.md",
                "README.pt-BR.md",
                "CODE_OF_CONDUCT.md",
                "SECURITY.md",
                "LICENSE",
                "NOTICE",
                "notes",
                // Site (MkDocs): configuração, tema e dependências Python.
                "mkdocs.yml",
                "overrides",
                "requirements-docs.txt",
                "VERSION",
                "docs",
                "Tests",
                "Info.plist",
                "create_xcode_project.sh",
                "create_installer.sh",
                "Makefile",
                "Installer",
                "Scripts",
                "Localization",
                // Saída de Scripts/bundle-app.sh, Installer/build-installer.sh e
                // create_installer.sh: o .app, o .pkg, o .dmg e a staging do .dmg
                // (que tem um symlink para /Applications — sem este exclude o SPM
                // seguiria o link e varreria /Applications inteiro), e o site do
                // MkDocs. Existe em todo clone por causa do build/.gitkeep.
                "build",
                "Assets.xcassets",
                "Design",
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
                "deep_clean.sh"
            ],
            sources: [
                "MACLIMPOApp.swift",
                "Models/CleaningCategory.swift",
                "Models/CleaningResult.swift",
                "Models/CleaningOptions.swift",
                "Models/Theme.swift",
                "Models/DiskXRay.swift",
                "Models/DiskScanIndex.swift",
                "Models/FileCategory.swift",
                "Services/CleaningService.swift",
                "Services/CleaningServiceRegistry.swift",
                "Services/AppleIntelligenceService.swift",
                "Services/PathBasedCleaningService.swift",
                "Services/DockerCleaningService.swift",
                "Services/DevPackagesCleaningService.swift",
                "Services/TempFilesCleaningService.swift",
                "Services/LogsCleaningService.swift",
                "Services/AppCacheCleaningService.swift",
                "Services/LaunchAtLoginService.swift",
                "Services/Logger.swift",
                "Services/DiskXRayService.swift",
                "Services/DiskScanner.swift",
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
                // Novos serviços para /var/folders e AI tools
                "Services/VarFoldersCleaningService.swift",
                "Services/AIToolsCleaningService.swift",
                "Services/CreativeAppsCleaningService.swift",
                "Services/PodcastsCleaningService.swift",
                "Services/AppLeftoversCleaningService.swift",
                "Services/ProjectCleaningService.swift",
                "Services/RustTargetsCleaningService.swift",
                // Novos serviços: pnpm, Go, API Tools, Notion, Cypress
                "Services/PnpmCleaningService.swift",
                "Services/GoCleaningService.swift",
                "Services/DevApiToolsCleaningService.swift",
                "Services/NotionCleaningService.swift",
                "Services/CypressCleaningService.swift",
                "Services/TikTokLiveStudioCleaningService.swift",
                "Services/NuGetCleaningService.swift",
                "Services/BunCleaningService.swift",
                "Services/PubCacheCleaningService.swift",
                "Services/GoogleCacheCleaningService.swift",
                "Services/NvmCleaningService.swift",
                "Services/AzureToolsCleaningService.swift",
                "Services/ExpoCleaningService.swift",
                "Services/ZedCleaningService.swift",
                "Services/AIModelsCleaningService.swift",
                "Services/DotnetSdkCleaningService.swift",
                // ViewModels
                "ViewModels/DiskXRayViewModel.swift",
                // Views
                "Views/MenuBarView.swift",
                "Views/NativeMenuBarView.swift",
                "Views/WelcomeView.swift",
                "Views/DiskXRayWindowView.swift",
                "Views/DiskXRayFileTree.swift",
                "Views/Components/CleaningCategoryCard.swift",
                "Views/Components/StorageStatsView.swift",
                "Views/Components/CleaningProgressView.swift",
                "Views/Components/CleaningConfirmationView.swift",
                "Views/Components/ResultsView.swift",
                "Views/Components/ThemePickerView.swift",
                "Views/Components/ThemeStyles.swift",
                // Utilities
                "Utilities/FileSystemHelper.swift",
                "Utilities/ShellExecutor.swift",
                "Utilities/PermissionsHelper.swift",
                "Utilities/NSAlert+MenuBar.swift",
                "Utilities/AsyncSemaphore.swift",
                "Utilities/Deadline.swift",
                "Utilities/TreemapRenderer.swift",
                "Utilities/TreemapMetal.swift",
                "Utilities/TreemapFlags.swift",
                "Utilities/SizeFormat.swift",
                "Utilities/ScanTuning.swift",
                "Views/Components/AppleIntelligenceInsightView.swift",
                "Intents/MACLIMPOIntents.swift"
            ]
        ),
        .testTarget(
            name: "MACLIMPOTests",
            dependencies: ["MAC-LIMPO"],
            path: "Tests/MACLIMPOTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
