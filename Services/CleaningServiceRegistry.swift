import Foundation

/// Single source of truth for every cleaner exposed by the app and by App Intents.
///
/// Keeping the registry outside the SwiftUI view model prevents integrations such
/// as Siri, Shortcuts and Apple Intelligence from creating a second, divergent
/// list of capabilities.
final class CleaningServiceRegistry: @unchecked Sendable {
    static let shared = CleaningServiceRegistry()

    let services: [CleaningCategory: any CleaningService]

    private init() {
        services = [
            .docker: DockerCleaningService(),
            .devPackages: DevPackagesCleaningService(),
            .tempFiles: TempFilesCleaningService(),
            .logs: LogsCleaningService(),
            .appCache: AppCacheCleaningService(),
            .xcodeCache: XcodeCacheCleaningService(),
            .iosSimulators: IOSSimulatorsCleaningService(),
            .downloads: DownloadsCleaningService(),
            .trash: TrashCleaningService(),
            .browserCache: BrowserCacheCleaningService(),
            .spotifyCache: SpotifyCacheCleaningService(),
            .slackCache: SlackCacheCleaningService(),
            .adobeCache: AdobeCleaningService(),
            .mailAttachments: MailAttachmentsCleaningService(),
            .messagesAttachments: MessagesAttachmentsCleaningService(),
            .ideCache: IDECacheCleaningService(),
            .androidSDK: AndroidSDKCleaningService(),
            .messagingApps: MessagingAppsCleaningService(),
            .playwright: PlaywrightCleaningService(),
            .cargo: CargoCleaningService(),
            .homebrew: HomebrewCleaningService(),
            .terminalLogs: TerminalLogsCleaningService(),
            .systemData: SystemDataCleaningService(),
            .varFolders: VarFoldersCleaningService(),
            .aiTools: AIToolsCleaningService(),
            .creativeApps: CreativeAppsCleaningService(),
            .podcasts: PodcastsCleaningService(),
            .appLeftovers: AppLeftoversCleaningService(),
            .development: ProjectCleaningService(),
            .rustTargets: RustTargetsCleaningService(),
            .pnpm: PnpmCleaningService(),
            .goCache: GoCleaningService(),
            .devApiTools: DevApiToolsCleaningService(),
            .notionCache: NotionCleaningService(),
            .cypress: CypressCleaningService(),
            .tiktokLiveStudio: TikTokLiveStudioCleaningService(),
            .nugetCache: NuGetCleaningService(),
            .bunCache: BunCleaningService(),
            .pubCache: PubCacheCleaningService(),
            .googleCache: GoogleCacheCleaningService(),
            .nvmVersions: NvmCleaningService(),
            .azureTools: AzureToolsCleaningService(),
            .expoCache: ExpoCleaningService(),
            .zedCache: ZedCleaningService(),
            .aiModels: AIModelsCleaningService(),
            .dotnetSdks: DotnetSdkCleaningService()
        ]
    }
}
