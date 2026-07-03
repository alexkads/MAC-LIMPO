import Foundation

/// Remove logs antigos do terminal Warp.
final class TerminalLogsCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .terminalLogs, targets: [
            CleanTarget("~/Library/Logs/warp.log", label: "Warp terminal logs"),
            CleanTarget("~/Library/Logs/warp.log.old.0"),
            CleanTarget("~/Library/Logs/warp.log.old.1"),
            CleanTarget("~/Library/Logs/warp.log.old.2"),
            CleanTarget("~/Library/Logs/warp.log.old.3"),
            CleanTarget("~/Library/Logs/warp.log.old.4")
        ])
    }
}
