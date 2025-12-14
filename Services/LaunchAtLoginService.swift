import Foundation
import ServiceManagement

class LaunchAtLoginService: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            updateState()
        }
    }
    
    init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }
    
    private func updateState() {
        do {
            if isEnabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("Failed to update Launch at Login state: \(error.localizedDescription)")
            // Revert state on failure usando Task em vez de DispatchQueue
            Task { @MainActor in
                self.isEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }
}
