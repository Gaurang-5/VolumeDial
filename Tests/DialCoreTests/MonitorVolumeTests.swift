import XCTest
@testable import VolumeDial

final class MonitorVolumeTests: XCTestCase {
    let known = MonitorLevel(id: "BENQ-UUID", name: "BenQ EW2790U", maximum: 50, value: 0.4)

    func testMonitorNamesMatchAcrossCaseAndSpacingDifferences() {
        let monitor = MonitorLevel(id: "LG-UUID", name: "LG HDR 4K", maximum: 100, value: 0.4)
        let result = MonitorVolume.matching(outputNames: ["lg hdr4k"], allOutputNames: ["lg hdr4k", "MacBook Pro Speakers"], monitors: [monitor])
        XCTAssertEqual(result.map(\.id), ["LG-UUID"])
    }

    func testDuplicateMonitorModelsAreNeverAssignedByGuessing() {
        let other = MonitorLevel(id: "SECOND-BENQ", name: "BENQ EW2790U", maximum: 50, value: 0.2)
        XCTAssertTrue(MonitorVolume.matching(outputNames: [known.name], allOutputNames: [known.name], monitors: [known, other]).isEmpty)
        XCTAssertTrue(MonitorVolume.matching(outputNames: [known.name], allOutputNames: [known.name, known.name], monitors: [known]).isEmpty)
        XCTAssertTrue(MonitorVolume.matching(outputNames: ["HDMI"], allOutputNames: ["HDMI"], monitors: [known]).isEmpty)
    }

    func testOtherMonitorBrandsUseTheirOwnVolumeRange() {
        let result = MonitorVolume.discover { arguments in
            if arguments == ["display", "list"] { return "[1] Dell U2723QE (DELL)\n[2] LG Display (LG)" }
            if arguments[1] == "DELL" { return arguments.contains("max") ? "100" : "20" }
            return arguments.contains("max") ? "255" : "51"
        }
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { abs($0.value - 0.2) < 0.0001 })
    }

    func testTransientProbeFailureKeepsConnectedMonitorControllable() {
        let result = MonitorVolume.discover(existing: [known]) { arguments in
            arguments == ["display", "list"] ? "[1] BenQ EW2790U (BENQ-UUID)" : nil
        }
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.maximum, 50)
        XCTAssertEqual(result.first?.value, 0.4)
    }

    func testFailedEnumerationKeepsKnownMonitorUntilDisconnectIsConfirmed() {
        XCTAssertEqual(MonitorVolume.discover(existing: [known], command: { _ in nil }).count, 1)
        XCTAssertTrue(MonitorVolume.discover(existing: [known], command: { _ in "" }).isEmpty)
    }

    func testReportedMaximumScalesFreshMonitorReading() {
        let result = MonitorVolume.discover { arguments in
            if arguments == ["display", "list"] { return "[1] BenQ EW2790U (BENQ-UUID)" }
            if arguments.contains("max") { return "50" }
            return "10"
        }
        XCTAssertEqual(result.first?.value, 0.2)
    }
}
