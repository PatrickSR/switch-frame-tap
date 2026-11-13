// SPDX-License-Identifier: GPL-2.0-only
import XCTest
@testable import SFTCore

final class PadTransmissionTests: XCTestCase {
    func testDisconnectReleasesHeldButtonsAndReconnectsNeutral() {
        var pad = PadTransmission()
        _ = pad.setActive(true, now: 0)
        _ = pad.update(PadState(buttons: .a, lx: 32767), now: 0.01)
        let release = pad.setActive(false, now: 0.02)
        XCTAssertEqual(release?.data, ViewerMessages.input(controller: false, state: PadState()))
        XCTAssertEqual(release?.droppable, false)
        XCTAssertNil(pad.heartbeat(now: 1))
        XCTAssertNil(pad.update(PadState(buttons: .home), now: 1.1))
        XCTAssertEqual(
            pad.setActive(true, now: 2)?.data,
            ViewerMessages.input(controller: true, state: PadState())
        )
    }

    func testRepeatedCapabilityDoesNotResetHeldInput() {
        var pad = PadTransmission()
        _ = pad.setActive(true, now: 0)
        let held = PadState(buttons: [.zr, .b])
        _ = pad.update(held, now: 0.01)
        XCTAssertNil(pad.setActive(true, now: 0.02))
        XCTAssertEqual(pad.heartbeat(now: 0.12)?.data, ViewerMessages.input(controller: true, state: held))
    }

    func testHidingOrSuspendingReleasesExactlyOnce() {
        var pad = PadTransmission()
        _ = pad.setActive(true, now: 0)
        _ = pad.update(PadState(buttons: .home, ry: -32767), now: 0.01)
        XCTAssertNotNil(pad.setActive(false, now: 0.02))
        XCTAssertNil(pad.setActive(false, now: 0.03))
        XCTAssertNil(pad.update(PadState(buttons: .a), now: 0.04))
        XCTAssertEqual(
            pad.setActive(true, now: 0.05)?.data,
            ViewerMessages.input(controller: true, state: PadState())
        )
    }

    func testOnlyUnchangedHeartbeatsMayBeDropped() {
        var pad = PadTransmission()
        XCTAssertEqual(pad.setActive(true, now: 0)?.droppable, false)
        XCTAssertNil(pad.heartbeat(now: 0.09))
        XCTAssertEqual(pad.heartbeat(now: 0.1)?.droppable, true)
        XCTAssertEqual(pad.update(PadState(buttons: .a), now: 0.11)?.droppable, false)
        XCTAssertEqual(pad.update(PadState(), now: 0.12)?.droppable, false)
        XCTAssertEqual(pad.setActive(false, now: 0.13)?.droppable, false)
    }
}
