import XCTest
import CoreGraphics
@testable import DialCore

final class DialCoreTests: XCTestCase {
    func testOutputPickerExcludesVirtualUtilitiesButKeepsGroups() {
        XCTAssertFalse(DialMath.showOutput(hasChannels: true, isVirtual: true, isAggregate: false, isHidden: false))
        XCTAssertTrue(DialMath.showOutput(hasChannels: true, isVirtual: true, isAggregate: true, isHidden: false))
        XCTAssertTrue(DialMath.showOutput(hasChannels: true, isVirtual: false, isAggregate: false, isHidden: false))
        XCTAssertFalse(DialMath.showOutput(hasChannels: false, isVirtual: false, isAggregate: false, isHidden: false))
        XCTAssertFalse(DialMath.showOutput(hasChannels: true, isVirtual: false, isAggregate: false, isHidden: true))
    }
    func testDialAngleMapsDirectlyToTwentyPercent() {
        XCTAssertEqual(DialMath.volume(atAngle: -171), 0.2, accuracy: 0.0001)
        XCTAssertEqual(DialMath.volume(atAngle: -90), 0.5, accuracy: 0.0001)
        XCTAssertEqual(DialMath.volume(atAngle: 135), 0, accuracy: 0.0001)
        XCTAssertEqual(DialMath.volume(atAngle: 45), 1, accuracy: 0.0001)
    }

    func testMonitorPercentageUsesReportedMaximum() {
        XCTAssertEqual(DialMath.hardwareValue(0.2, maximum: 50), 10)
        XCTAssertEqual(DialMath.hardwareValue(0.8, maximum: 50), 40)
        XCTAssertEqual(DialMath.hardwareValue(1, maximum: 50), 50)
    }

    func testPanelStaysBelowMenuBarAndInsideRightEdge() {
        let frame = DialMath.panelFrame(anchor: CGRect(x: 1400, y: 880, width: 36, height: 24), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 880), size: CGSize(width: 340, height: 510))
        XCTAssertEqual(frame, CGRect(x: 1092, y: 362, width: 340, height: 510))
    }

    func testPanelFitsSecondaryScreenWithNegativeCoordinates() {
        let visible = CGRect(x: -1920, y: -800, width: 1920, height: 1056)
        let frame = DialMath.panelFrame(anchor: CGRect(x: -40, y: 256, width: 36, height: 24), visibleFrame: visible, size: CGSize(width: 340, height: 510))
        XCTAssertTrue(visible.contains(frame))
        XCTAssertEqual(frame.maxY, 248)
        XCTAssertEqual(frame.maxX, -8)
    }

    func testRestoreOnlyTouchesCurrentMembersAndPreservesNewMembersLevel() {
        let restored = DialMath.restorationValues(current: ["speaker": 0, "new": 0.4], saved: ["speaker": 0.7, "removed": 0.9])
        XCTAssertEqual(restored, ["speaker": 0.7, "new": 0.4])
    }

    func testExternalHardwareMuteRetainsItsRawVolume() {
        XCTAssertEqual(DialMath.restorationValues(current: ["headphones": 0.63], saved: [:]), ["headphones": 0.63])
        XCTAssertEqual(DialMath.restorationValues(current: ["speaker": 0.0], saved: [:]), ["speaker": 0.25])
    }

    func testVolumeStopsAtBothLimits() {
        XCTAssertEqual(DialMath.clamp(-0.2), 0)
        XCTAssertEqual(DialMath.clamp(1.2), 1)
        XCTAssertEqual(DialMath.clamp(0.37), 0.37)
        XCTAssertEqual(DialMath.clamp(.nan), 0)
    }

    func testCrossingAngleSeamDoesNotJumpVolume() {
        XCTAssertEqual(DialMath.rotationDelta(from: 179, to: -179), 2, accuracy: 0.001)
        XCTAssertEqual(DialMath.rotationDelta(from: -179, to: 179), -2, accuracy: 0.001)
    }

    func testGroupAdjustmentSetsEveryMemberToTheRequestedPercentage() {
        let balanced = DialMath.shiftedVolumes([0.2, 0.6], to: 0.5)
        XCTAssertEqual(balanced.count, 2)
        guard balanced.count == 2 else { return }
        XCTAssertEqual(balanced[0], 0.5, accuracy: 0.001)
        XCTAssertEqual(balanced[1], 0.5, accuracy: 0.001)
        let values = DialMath.shiftedVolumes([0.2, 0.6], to: 0.95)
        XCTAssertEqual(values.count, 2)
        guard values.count == 2 else { return }
        XCTAssertEqual(values[0], 0.95, accuracy: 0.001)
        XCTAssertEqual(values[1], 0.95, accuracy: 0.001)
        XCTAssertEqual(DialMath.shiftedVolumes([], to: 0.8), [])
    }

    func testZeroSilencesEveryMemberAndFullVolumeReachesAllMembers() {
        XCTAssertEqual(DialMath.shiftedVolumes([0.2, 0.6], to: 0), [0, 0])
        XCTAssertEqual(DialMath.shiftedVolumes([0.2, 0.6], to: 1), [1, 1])
    }
}
