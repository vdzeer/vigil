import ServiceManagement

/// Starting the app when you log in. It shows up in System Settings → General → Login Items.
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Run from /Applications or ~/Applications, not from the disk image, Downloads or a moved copy.
    static var isInstalled: Bool {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return folder == "/Applications" || folder == home
    }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
                // macOS may want the user to allow it first; System Settings opens at the right place.
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
