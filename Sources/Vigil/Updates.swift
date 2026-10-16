import AppKit
import Sparkle
import VigilCore

/// Updates from GitHub Releases through Sparkle; the feed and the signing key are in Info.plist.
/// Sparkle looks once a day and downloads a new version in the background. Vigil installs it on
/// its own while the lid is open and starts again, which takes a second. A restart, also one the
/// user asks for, keeps lid-closed mode on and the Mac awake until the new version takes over.
final class Updates: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    private var pending: (() -> Void)?
    /// Set just before Sparkle quits Vigil to start the new version.
    private(set) var isRestarting = false

    override init() {
        super.init()
        // A build run straight from `swift build` has no Info.plist and so no feed: no updates.
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    var isAvailable: Bool { controller != nil }

    func checkNow() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    /// Call when the lid may have opened. With the lid closed nobody is there to see the restart
    /// go wrong, so an update that arrives then waits.
    func installIfLidOpen() {
        guard let install = pending, !LidSensor.isClosed() else { return }
        pending = nil
        install()
    }

    nonisolated func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // Sparkle calls its delegate on the main thread.
        nonisolated(unsafe) let install = immediateInstallHandler
        MainActor.assumeIsolated {
            pending = install
            installIfLidOpen()
        }
        return true
    }

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        MainActor.assumeIsolated {
            isRestarting = true
            AwakeHold.bridgeRestart()
        }
    }
}
