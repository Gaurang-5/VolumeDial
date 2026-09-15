import XCTest
@testable import DialCore

final class VolumeRequestTests: XCTestCase {
    func testOldOutputGestureCannotAdjustNewOutput() {
        let request = VolumeRequest(outputID: 74, value: 0.2)
        XCTAssertTrue(request.canApply(currentOutputID: 74, isSwitching: false))
        XCTAssertFalse(request.canApply(currentOutputID: 140, isSwitching: false))
    }
    func testGesturesCannotWriteDuringRoutingTransition() {
        XCTAssertFalse(VolumeRequest(outputID: 74, value: 0.8).canApply(currentOutputID: 74, isSwitching: true))
        XCTAssertFalse(VolumeRequest(outputID: 0, value: 0.8).canApply(currentOutputID: 0, isSwitching: false))
    }
}
