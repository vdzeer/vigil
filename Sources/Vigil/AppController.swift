import AppKit
import VigilCore

/// The whole app: one menu bar item. A click keeps the Mac awake or lets it sleep again;
/// a right click (or Control-click) opens the menu with the lid-closed switch.
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Key {
        static let awake = "awake"
        static let lid = "lid"
        static let loginItemOffered = "loginItemOffered"
    }

    private let defaults = UserDefaults.standard
    private let hold = AwakeHold()
    private let watchdog = LidWatchdog()
    /// Keeps App Nap from stretching the battery guard's timer while lid-closed mode is on.
    private var lidActivity: NSObjectProtocol?

    private var item: NSStatusItem!
    private let menu = NSMenu()
    private var awakeItem: NSMenuItem!
    private var lidItem: NSMenuItem!
    private var noteItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var ticker: Task<Void, Never>?

    private var state = VigilState()

    // MARK: - life cycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Strings.appName
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        buildMenu()

        hold.set(defaults.bool(forKey: Key.awake))
        state.awake = hold.isOn
        render()

        // The first launch from an Applications folder puts the app among the login items; after
        // that the menu decides. A copy run from the disk image or a download folder is not added.
        if !defaults.bool(forKey: Key.loginItemOffered), LoginItem.isInstalled, LoginItem.set(true) {
            defaults.set(true, forKey: Key.loginItemOffered)
        }

        // Lid-closed mode is a system setting that outlives the app, so it is put back the way
        // it was left; from then on the app shows whatever the system says.
        let wantLid = defaults.bool(forKey: Key.lid)
        Task.detached {
            let lowBattery = BatteryGuard.shouldReleaseLid(lidOn: true, percentOnBattery: Battery.percentOnBattery())
            if wantLid, !lowBattery, !LidMode.isOn(), LidMode.isReady() { LidMode.set(true) }
            let reading = Self.readLid()
            await self.apply(reading)
        }

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.tick()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(woke(_:)), name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// While the app is not running, nothing keeps the Mac awake.
    func applicationWillTerminate(_ notification: Notification) {
        ticker?.cancel()
        hold.set(false)
        // Asks the system rather than `state`: a switch or the start-up restore may still be under way.
        if LidMode.isOn() { LidMode.set(false) }
        watchdog.stop()
    }

    // MARK: - menu bar item

    private func buildMenu() {
        menu.autoenablesItems = false
        menu.delegate = self
        awakeItem = add(Strings.Menu.keepAwake, #selector(toggleAwake(_:)))
        lidItem = add(Strings.Menu.lidClosed, #selector(toggleLid(_:)))
        noteItem = add("", nil)
        noteItem.isEnabled = false
        menu.addItem(.separator())
        loginItem = add(Strings.Menu.openAtLogin, #selector(toggleLoginItem(_:)))
        add(Strings.Menu.about, #selector(about(_:)))
        add(Strings.Menu.quit, #selector(quit(_:)), key: "q")
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    @objc private func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            toggleAwake(nil)
        }
    }

    private func showMenu() {
        // With a menu attached the item would open it on every click; it is attached only for this one.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // `pmset -g` answers in a few milliseconds; the menu must show the real state when it opens.
        state.lid = LidMode.isOn()
        render()
    }

    private func render() {
        let shown = Presentation(state)
        item.button?.image = Glyph.statusImage(shown.icon)
        item.button?.toolTip = shown.tooltip
        item.button?.setAccessibilityLabel(shown.icon.label)

        awakeItem.state = shown.awakeChecked ? .on : .off
        lidItem.state = shown.lidChecked ? .on : .off
        lidItem.isEnabled = shown.lidEnabled
        loginItem.state = LoginItem.isOn ? .on : .off
        noteItem.title = shown.note ?? ""
        noteItem.isHidden = shown.note == nil
    }

    // MARK: - actions

    @objc private func toggleAwake(_ sender: Any?) {
        hold.set(!hold.isOn)
        state.awake = hold.isOn
        defaults.set(hold.isOn, forKey: Key.awake)
        render()
    }

    @objc private func toggleLid(_ sender: Any?) {
        guard !state.lidBusy else { return }
        state.lidBusy = true
        render()
        let want = !state.lid
        let script = Bundle.main.path(forResource: "allow-lid-closed", ofType: "sh")
        let user = NSUserName()
        Task.detached {
            var done = LidMode.set(want)
            // It failed: the one-time admin step is missing or was undone. The password dialog can
            // stay open for as long as the user likes.
            if !done, let script { done = await LidMode.runSetup(script: script, user: user) && LidMode.set(want) }
            let reading = Self.readLid()
            await self.apply(reading, note: done ? nil : .changeFailed, finishing: true)
        }
    }

    @objc private func toggleLoginItem(_ sender: Any?) {
        LoginItem.set(!LoginItem.isOn)
        render()
    }

    @objc private func about(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: Strings.aboutCredits,
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
        ])
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - keeping in step with the system

    @objc private func woke(_ notification: Notification) {
        tick()
    }

    private func tick() {
        Task.detached {
            var note: Note?
            let lidOn = LidMode.isOn()
            if BatteryGuard.shouldReleaseLid(lidOn: lidOn, percentOnBattery: Battery.percentOnBattery()),
                LidMode.set(false)
            {
                note = .lowBattery(BatteryGuard.lowBattery)
            }
            let reading = Self.readLid()
            await self.apply(reading, note: note, keepingNote: note == nil)
        }
    }

    /// The real lid setting and whether the admin step is done. Blocks while `pmset` and `sudo` run.
    nonisolated private static func readLid() -> (on: Bool, ready: Bool) {
        let on = LidMode.isOn()
        return (on, on || LidMode.isReady())
    }

    /// Shows what the system says. The saved wish follows it.
    private func apply(
        _ reading: (on: Bool, ready: Bool), note: Note? = nil, keepingNote: Bool = false, finishing: Bool = false
    ) {
        state.lid = reading.on
        state.lidReady = reading.ready
        if reading.on {
            watchdog.start()
            if lidActivity == nil {
                lidActivity = ProcessInfo.processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep, reason: Strings.assertionName)
            }
        } else {
            watchdog.stop()
            if let lidActivity { ProcessInfo.processInfo.endActivity(lidActivity) }
            lidActivity = nil
        }
        if finishing { state.lidBusy = false }
        if !keepingNote { state.note = note }
        defaults.set(reading.on, forKey: Key.lid)
        render()
    }
}
