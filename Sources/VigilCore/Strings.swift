/// Every word Vigil shows. Title case for menu items, sentence case for notes; no exclamation marks.
public enum Strings {
    public static let appName = "Vigil"

    public enum Menu {
        public static let keepAwake = "Keep Mac Awake"
        public static let lidClosed = "Keep Running with Lid Closed"
        public static let openAtLogin = "Open at Login"
        public static let about = "About Vigil"
        public static let quit = "Quit Vigil"
    }

    public enum Note {
        public static let needsPassword = "Asks for an administrator password the first time"
        public static let changeFailed = "Couldn’t change the sleep setting"
        public static func lowBattery(_ percent: Int) -> String { "Turned off: battery below \(percent)%" }
    }

    public enum Tooltip {
        public static let awake = "Vigil is keeping your Mac awake. Click to let it sleep. Right-click for the menu."
        public static let asleep = "Click to keep your Mac awake. Right-click for the menu."
    }

    public enum Icon {
        public static let asleep = "Vigil, your Mac may sleep"
        public static let awake = "Vigil, keeping your Mac awake"
        public static let lidIdle = "Vigil, running with the lid closed"
        public static let lidAwake = "Vigil, running with the lid closed and keeping your Mac awake"
    }

    /// Shown in the macOS password dialog for the one-time admin step.
    public static let adminPrompt = "Vigil wants to let your Mac keep running with its lid closed."

    /// Shown by `pmset -g assertions`, which prints plain ASCII only.
    public static let assertionName = "Vigil is keeping the Mac awake"

    public static let aboutCredits =
        "Keeps your Mac awake, even with the lid closed.\nMIT License · github.com/vdzeer/vigil"
}
