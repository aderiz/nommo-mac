import ServiceManagement

/// Launch at login, through the system's Login Items (System Settings, General, Login Items).
public enum LoginItem {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS sometimes needs the user to approve a new login item in System Settings first.
    public static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    public static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: "enabled"
        case .notRegistered: "not registered"
        case .requiresApproval: "requires approval in System Settings, General, Login Items"
        case .notFound: "not found"
        @unknown default: "unknown"
        }
    }

    public static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
