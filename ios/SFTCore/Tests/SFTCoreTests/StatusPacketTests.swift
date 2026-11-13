// SPDX-License-Identifier: GPL-2.0-only
import XCTest
@testable import SFTCore

final class StatusPacketTests: XCTestCase {
    func testReasonHeadDetail() throws {
        var payload = Data(repeating: 0, count: 192)
        payload.replaceSubrange(4 ..< 8, with: le32(1))
        let head = Data("Connected - no game is running".utf8)
        let detail = Data("Start a game.".utf8)
        payload.replaceSubrange(8 ..< 8 + head.count, with: head)
        payload.replaceSubrange(72 ..< 72 + detail.count, with: detail)
        let packet = try PacketReader().feed(wire(flags: 24, seq: 3, payload: payload), receivedAt: 0)[0]
        let status = StatusPacket(packet: packet)
        XCTAssertTrue(packet.isStatus)
        XCTAssertFalse(packet.isAudio)
        XCTAssertEqual(status.reason, 1)
        XCTAssertEqual(status.head, "Connected - no game is running")
        XCTAssertEqual(status.detail, "Start a game.")
    }

    func testShortPayloadSafe() {
        let eight = StatusPacket(Data([0, 0, 0, 0, 9, 0, 0, 0]))
        XCTAssertEqual(eight.reason, 9)
        XCTAssertEqual(eight.head, "")
        XCTAssertEqual(eight.detail, "")
        let short = StatusPacket(Data([1, 2, 3]))
        XCTAssertEqual(short.reason, 0)
        XCTAssertEqual(short.head, "")
        XCTAssertEqual(short.detail, "")
    }

    func testStringsStopAtNulAndLimit() {
        var payload = Data(repeating: 0x41, count: 192)
        payload[4] = 2
        payload[5] = 0
        payload[6] = 0
        payload[7] = 0
        payload[8 + 64 - 1] = 0
        payload[72 + 10] = 0
        let status = StatusPacket(payload)
        XCTAssertEqual(status.reason, 2)
        XCTAssertEqual(status.head, String(repeating: "A", count: 63))
        XCTAssertEqual(status.detail, String(repeating: "A", count: 10))
    }
}
