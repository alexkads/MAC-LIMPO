import Foundation

/// Remove os caches de browsers do Playwright.
final class PlaywrightCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .playwright, targets: [
            CleanTarget("~/Library/Caches/ms-playwright"),
            CleanTarget("~/Library/Caches/ms-playwright-go")
        ])
    }
}
