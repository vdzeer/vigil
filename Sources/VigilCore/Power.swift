import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// Runs a command and returns its exit status and what it printed.
@discardableResult
public func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return (-1, "")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

/// Keeps the display on and the Mac from idling to sleep, the way Caffeine does.
/// macOS drops the hold by itself when the app quits.
public final class AwakeHold {
    private var id = IOPMAssertionID(0)
    public private(set) var isOn = false

    public init() {}

    public func set(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                Strings.assertionName as CFString,
                &id
            )
            isOn = result == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(id)
            isOn = false
        }
    }
}

/// "Keep running with the lid closed". This is the system-wide SleepDisabled setting, which
/// only an administrator may change; `allow-lid-closed.sh` lets this account flip exactly that
/// one setting without a password. Every call blocks while a command runs: keep them off the
/// main thread.
public enum LidMode {
    static let pmset = "/usr/bin/pmset"
    static let sudo = "/usr/bin/sudo"
    static let rule = "/etc/sudoers.d/vigil"

    public static func isOn() -> Bool {
        isOn(pmsetOutput: run(pmset, ["-g"]).output)
    }

    /// Reads SleepDisabled from the output of `pmset -g`.
    public static func isOn(pmsetOutput: String) -> Bool {
        pmsetOutput.range(of: #"(?m)^\s*SleepDisabled\s+1\b"#, options: .regularExpression) != nil
    }

    /// Whether the one-time admin step has been done: its rule file is in place. `sudo -n -l` cannot
    /// tell, because for an administrator with any password-free rule it also lists every command
    /// that would still ask for the password. Whether the rule works is known only from `set`.
    public static func isReady() -> Bool {
        FileManager.default.fileExists(atPath: rule)
    }

    @discardableResult
    public static func set(_ on: Bool) -> Bool {
        run(sudo, ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"]).status == 0
    }

    /// Does the one-time admin step through the standard macOS password dialog. The script runs
    /// inside the app rather than through `osascript`, so the dialog names Vigil. AppleScript runs
    /// on the main thread; the menu waits while the dialog is open.
    @MainActor
    public static func runSetup(script: String, user: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: setupScript(script: script, user: user))?.executeAndReturnError(&error)
        return error == nil
    }

    /// The AppleScript line that runs the setup script as root. Both values are quoted twice,
    /// for the shell and for AppleScript, so no character in a path or user name can escape.
    public static func setupScript(script: String, user: String) -> String {
        let command = "\(shellQuoted(script)) --user \(shellQuoted(user))"
        return "do shell script \(scriptQuoted(command)) with prompt \(scriptQuoted(Strings.adminPrompt))"
            + " with administrator privileges"
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    static func scriptQuoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Turns lid-closed mode off when the app dies without doing so itself, after a crash or Force
/// Quit: the setting is stored on disk and would keep a closed Mac awake until Vigil runs again.
/// A small shell process waits for the app to go away; it does nothing if another copy of Vigil
/// for this user is running by then.
public final class LidWatchdog {
    private var process: Process?

    public init() {}

    public var isRunning: Bool { process?.isRunning ?? false }

    public func start() {
        guard !isRunning else { return }
        let watcher = Process()
        watcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        watcher.arguments = ["-c", Self.script(pid: ProcessInfo.processInfo.processIdentifier, uid: getuid())]
        watcher.standardInput = FileHandle.nullDevice
        watcher.standardOutput = FileHandle.nullDevice
        watcher.standardError = FileHandle.nullDevice
        do {
            try watcher.run()
            process = watcher
        } catch {
            process = nil
        }
    }

    /// The app switched the mode off itself; the watcher is no longer needed.
    public func stop() {
        if isRunning { process?.terminate() }
        process = nil
    }

    /// Only numbers go into the line, and every command is called by its full path.
    public static func script(pid: Int32, uid: uid_t) -> String {
        "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 5; done; "
            + "/usr/bin/pgrep -xq -U \(uid) \(Strings.appName) || "
            + "\(LidMode.sudo) -n \(LidMode.pmset) -a disablesleep 0"
    }
}

public enum Battery {
    /// Charge in percent while the Mac runs on its battery; nil when it is plugged in or has none.
    public static func percentOnBattery() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let about = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                about[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                about[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                let now = about[kIOPSCurrentCapacityKey] as? Int,
                let full = about[kIOPSMaxCapacityKey] as? Int, full > 0
            else { continue }
            return now * 100 / full
        }
        return nil
    }
}
