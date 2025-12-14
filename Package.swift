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
                "Info.plist",
                "create_xcode_project.sh",
                "Assets.xcassets",
                "Design"
            ],
            sources: [
                "MACLIMPOApp.swift",
                "Models/CleaningCategory.swift",
                "Models/CleaningResult.swift",
                "Services/CleaningService.swift",
                "Services/DockerCleaningService.swift",
                "Services/DevPackagesCleaningService.swift",
                "Services/TempFilesCleaningService.swift",
                "Services/LogsCleaningService.swift",
                "Services/LogsCleaningService.swift",
                "Services/AppCacheCleaningService.swift",
                "Services/LaunchAtLoginService.swift",
                "Views/MenuBarView.swift",
                "Views/Components/CleaningCategoryCard.swift",
                "Views/Components/StorageStatsView.swift",
                "Views/Components/CleaningProgressView.swift",
                "Views/Components/ResultsView.swift",
                "Utilities/FileSystemHelper.swift",
                "Utilities/ShellExecutor.swift"
            ]
        )
    ]
)
