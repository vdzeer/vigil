/// What Vigil knows at a given moment.
public struct VigilState: Equatable, Sendable {
    /// The idle-sleep hold is on.
    public var awake: Bool
    /// The system-wide SleepDisabled setting is on, so the Mac keeps running with its lid closed.
    public var lid: Bool
    /// The one-time admin step is done, so the lid setting can change without a password.
    public var lidReady: Bool
    /// A change of the lid setting is in progress (the password dialog may be open).
    public var lidBusy: Bool
    public var note: Note?

    public init(awake: Bool = false, lid: Bool = false, lidReady: Bool = true, lidBusy: Bool = false, note: Note? = nil)
    {
        self.awake = awake
        self.lid = lid
        self.lidReady = lidReady
        self.lidBusy = lidBusy
        self.note = note
    }
}

/// Something that happened and stays in the menu until the next change.
public enum Note: Equatable, Sendable {
    case lowBattery(Int)
    case changeFailed
}

/// The four menu bar pictures. They differ in shape, not colour: template images take the
/// menu bar's own colour and stay readable on any wallpaper.
public enum IconKind: Equatable, Sendable, CaseIterable {
    /// A closed eye: the Mac may sleep.
    case asleep
    /// An open eye: the Mac is kept awake.
    case awake
    /// A laptop with a closed eye: the Mac keeps running with its lid closed, the display may idle.
    case lidIdle
    /// A laptop with an open eye: both switches are on.
    case lidAwake

    public init(awake: Bool, lid: Bool) {
        switch (awake, lid) {
        case (false, false): self = .asleep
        case (true, false): self = .awake
        case (false, true): self = .lidIdle
        case (true, true): self = .lidAwake
        }
    }

    public var label: String {
        switch self {
        case .asleep: Strings.Icon.asleep
        case .awake: Strings.Icon.awake
        case .lidIdle: Strings.Icon.lidIdle
        case .lidAwake: Strings.Icon.lidAwake
        }
    }
}

/// Everything the menu bar item shows, worked out from the state alone.
public struct Presentation: Equatable, Sendable {
    public let icon: IconKind
    public let tooltip: String
    public let awakeChecked: Bool
    public let lidChecked: Bool
    public let lidEnabled: Bool
    /// The grey line under the lid switch; nil hides it.
    public let note: String?

    public init(_ state: VigilState) {
        icon = IconKind(awake: state.awake, lid: state.lid)
        tooltip = state.awake ? Strings.Tooltip.awake : Strings.Tooltip.asleep
        awakeChecked = state.awake
        lidChecked = state.lid
        lidEnabled = !state.lidBusy
        switch state.note {
        case .lowBattery(let percent): note = Strings.Note.lowBattery(percent)
        case .changeFailed: note = Strings.Note.changeFailed
        case nil: note = state.lidReady || state.lid ? nil : Strings.Note.needsPassword
        }
    }
}

public enum BatteryGuard {
    /// On battery below this charge, lid-closed mode is switched off: a shut Mac that never
    /// sleeps would otherwise drain itself flat.
    public static let lowBattery = 15

    /// `percentOnBattery` is nil while the Mac is plugged in.
    public static func shouldReleaseLid(lidOn: Bool, percentOnBattery: Int?) -> Bool {
        guard lidOn, let percent = percentOnBattery else { return false }
        return percent < lowBattery
    }
}
