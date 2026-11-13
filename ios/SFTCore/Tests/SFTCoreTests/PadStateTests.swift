// SPDX-License-Identifier: GPL-2.0-only
import XCTest
@testable import SFTCore

final class PadStateTests: XCTestCase {
    func testStickFullDeflection() {
        XCTAssertTrue(PadState.normalizedStick(x: 1, y: 0) == (32767, 0))
        XCTAssertTrue(PadState.normalizedStick(x: -1, y: 0) == (-32767, 0))
        XCTAssertTrue(PadState.normalizedStick(x: 0, y: -1) == (0, 32767))
        XCTAssertTrue(PadState.normalizedStick(x: 0, y: 1) == (0, -32767))
    }

    func testStickDiagonalStaysOnCircle() {
        XCTAssertTrue(PadState.normalizedStick(x: -1, y: 1) == (-23169, -23169))
        XCTAssertTrue(PadState.normalizedStick(x: 1, y: -1) == (23169, 23169))
    }

    func testStickDeadZone() {
        XCTAssertTrue(PadState.normalizedStick(x: 0.05, y: -0.05) == (0, 0))
        XCTAssertTrue(PadState.normalizedStick(x: 0, y: 0) == (0, 0))
        let (x, _) = PadState.normalizedStick(x: 0.081, y: 0)
        XCTAssertGreaterThan(x, 0)
        XCTAssertLessThan(x, 200)
        let expected = Int32((0.5 * 32767 - 2621.36) / (32767 - 2621.36) * 32767)
        XCTAssertTrue(PadState.normalizedStick(x: 0.5, y: 0) == (expected, 0))
    }

    func testStickNonFiniteIsNeutral() {
        XCTAssertTrue(PadState.normalizedStick(x: .nan, y: 0) == (0, 0))
        XCTAssertTrue(PadState.normalizedStick(x: .infinity, y: .infinity) == (0, 0))
        XCTAssertTrue(PadState.normalizedStick(x: 0, y: -.infinity) == (0, 0))
    }

    func testSendSchedule() {
        var schedule = PadSendSchedule()
        let idle = PadState()
        XCTAssertTrue(schedule.shouldSend(state: idle, now: 0))
        XCTAssertFalse(schedule.shouldSend(state: idle, now: 0.05))
        XCTAssertFalse(schedule.shouldSend(state: idle, now: 0.099))
        XCTAssertTrue(schedule.shouldSend(state: idle, now: 0.1))
        XCTAssertFalse(schedule.shouldSend(state: idle, now: 0.15))
        let pressed = PadState(buttons: [.a])
        XCTAssertTrue(schedule.shouldSend(state: pressed, now: 0.16))
        XCTAssertFalse(schedule.shouldSend(state: pressed, now: 0.2))
        XCTAssertTrue(schedule.shouldSend(state: idle, now: 0.21))
    }

    func testSendScheduleReset() {
        var schedule = PadSendSchedule()
        let idle = PadState()
        XCTAssertTrue(schedule.shouldSend(state: idle, now: 1))
        schedule.reset()
        XCTAssertTrue(schedule.shouldSend(state: idle, now: 1.01))
    }
}
