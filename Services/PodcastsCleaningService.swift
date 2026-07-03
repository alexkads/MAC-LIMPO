import Foundation

/// Remove episódios baixados e caches do app Podcasts (preserva as pastas).
final class PodcastsCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .podcasts, targets: [
            CleanTarget(
                "~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Documents",
                label: "Downloaded Episodes",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache",
                label: "Cache",
                strategy: .removeContents
            ),
            CleanTarget(
                "~/Library/Containers/com.apple.podcasts/Data/Library/Caches",
                label: "Cache",
                strategy: .removeContents
            ),
            CleanTarget("~/Library/Caches/com.apple.podcasts", label: "Cache", strategy: .removeContents)
        ])
    }
}
