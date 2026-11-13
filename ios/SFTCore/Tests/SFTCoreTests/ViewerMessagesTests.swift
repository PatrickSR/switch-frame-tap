// SPDX-License-Identifier: GPL-2.0-only
import XCTest
@testable import SFTCore

final class ViewerMessagesTests: XCTestCase {
    func testKeyframeRequest() {
        XCTAssertEqual(ViewerMessages.keyframe, Data([0x53, 0x46, 0x54, 0x4B]))
    }

    func testSFTIGoldenBytes() {
        let state = PadState(buttons: [.a, .zr, .capture], lx: 32767, ly: -32767, rx: 1, ry: -2)
        let want = Data([
            0x53, 0x46, 0x54, 0x49,
            0x01, 0x00, 0x00, 0x00,
            0x01, 0x02, 0x08, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0xFF, 0x7F, 0x00, 0x00,
            0x01, 0x80, 0xFF, 0xFF,
            0x01, 0x00, 0x00, 0x00,
            0xFE, 0xFF, 0xFF, 0xFF,
        ])
        XCTAssertEqual(ViewerMessages.input(controller: true, state: state), want)
    }

    func testReleaseMessage() {
        let message = ViewerMessages.input(controller: false, state: PadState(buttons: [.a], lx: 1))
        XCTAssertEqual(message.count, 32)
        XCTAssertEqual(message[4], 0)
    }

    func testButtonsAre64Bit() {
        let state = PadState(buttons: PadButtons(rawValue: 1 << 40))
        let message = ViewerMessages.input(controller: true, state: state)
        XCTAssertEqual(message[13], 1)
    }
}
