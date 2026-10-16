import Testing

@testable import VigilCore

@Suite struct PresentationTests {
    @Test(arguments: [
        (false, false, IconKind.asleep), (true, false, .awake), (false, true, .lidIdle), (true, true, .lidAwake),
    ])
    func everyStateHasItsOwnShape(awake: Bool, lid: Bool, expected: IconKind) {
        #expect(Presentation(VigilState(awake: awake, lid: lid)).icon == expected)
    }

    @Test func theFourShapesHaveFourLabels() {
        #expect(Set(IconKind.allCases.map(\.label)).count == IconKind.allCases.count)
    }

    @Test func theTooltipSaysWhatAClickWillDo() {
        #expect(Presentation(VigilState(awake: true)).tooltip == Strings.Tooltip.awake)
        #expect(Presentation(VigilState(awake: false)).tooltip == Strings.Tooltip.asleep)
    }

    @Test func checkmarksFollowTheState() {
        let shown = Presentation(VigilState(awake: true, lid: false))
        #expect(shown.awakeChecked)
        #expect(!shown.lidChecked)
    }

    @Test func theLidSwitchWaitsWhileAChangeIsInProgress() {
        #expect(!Presentation(VigilState(lidBusy: true)).lidEnabled)
        #expect(Presentation(VigilState(lidBusy: false)).lidEnabled)
    }

    @Test func warnsAboutThePasswordOnlyBeforeTheAdminStep() {
        #expect(Presentation(VigilState(lid: false, lidReady: false)).note == Strings.Note.needsPassword)
        #expect(Presentation(VigilState(lid: false, lidReady: true)).note == nil)
        #expect(Presentation(VigilState(lid: true, lidReady: false)).note == nil)
    }

    @Test func aNoteWinsOverThePasswordHint() {
        let low = Presentation(VigilState(lidReady: false, note: .lowBattery(15)))
        #expect(low.note == "Turned off: battery below 15%")
        #expect(Presentation(VigilState(note: .changeFailed)).note == Strings.Note.changeFailed)
    }
}

@Suite struct BatteryGuardTests {
    @Test func releasesTheLidOnlyOnALowBattery() {
        #expect(BatteryGuard.shouldReleaseLid(lidOn: true, percentOnBattery: 14))
        #expect(!BatteryGuard.shouldReleaseLid(lidOn: true, percentOnBattery: 15))
        #expect(!BatteryGuard.shouldReleaseLid(lidOn: true, percentOnBattery: nil))
        #expect(!BatteryGuard.shouldReleaseLid(lidOn: false, percentOnBattery: 3))
    }
}
