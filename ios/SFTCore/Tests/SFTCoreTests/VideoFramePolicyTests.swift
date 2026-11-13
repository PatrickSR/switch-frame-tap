// SPDX-License-Identifier: GPL-2.0-only
import XCTest
@testable import SFTCore

final class VideoFramePolicyTests: XCTestCase {
    func testInitialWaitsForIDR() {
        var policy = VideoFramePolicy()
        var d = policy.consume(header(2, seq: 0), now: 0)
        XCTAssertEqual(d, .init(decode: false, resetDecoder: false, requestKeyframe: true))
        XCTAssertEqual(policy.droppedCount, 1)
        d = policy.consume(header(6, seq: 1), now: 0.1)
        XCTAssertEqual(d, .init(decode: true, resetDecoder: true, requestKeyframe: false))
        XCTAssertFalse(policy.waitingForIDR)
        d = policy.consume(header(2, seq: 2), now: 0.2)
        XCTAssertEqual(d, .init(decode: true, resetDecoder: false, requestKeyframe: false))
    }

    func testSequenceGapResets() {
        var policy = VideoFramePolicy()
        _ = policy.consume(header(6, seq: 5), now: 0)
        _ = policy.consume(header(2, seq: 6), now: 0.1)
        var d = policy.consume(header(2, seq: 8), now: 0.2)
        XCTAssertEqual(d, .init(decode: false, resetDecoder: false, requestKeyframe: true))
        XCTAssertEqual(policy.resetCount, 1)
        d = policy.consume(header(2, seq: 9), now: 0.6)
        XCTAssertEqual(d, .init(decode: false, resetDecoder: false, requestKeyframe: true))
        d = policy.consume(header(6, seq: 10), now: 0.7)
        XCTAssertEqual(d, .init(decode: true, resetDecoder: true, requestKeyframe: false))
        XCTAssertEqual(policy.lastSequence, 10)
    }

    func testGapIDRRecoversInSameCall() {
        var policy = VideoFramePolicy()
        _ = policy.consume(header(6, seq: 1), now: 0)
        let d = policy.consume(header(6, seq: 9), now: 0.1)
        XCTAssertEqual(d, .init(decode: true, resetDecoder: true, requestKeyframe: false))
        XCTAssertEqual(policy.resetCount, 1)
        XCTAssertEqual(policy.lastSequence, 9)
    }

    func testSequenceWrap() {
        var policy = VideoFramePolicy()
        _ = policy.consume(header(6, seq: 0xFFFF_FFFF), now: 0)
        let d = policy.consume(header(2, seq: 0), now: 0.1)
        XCTAssertEqual(d, .init(decode: true, resetDecoder: false, requestKeyframe: false))
    }

    func testResolutionChangeResets() {
        var policy = VideoFramePolicy()
        _ = policy.consume(header(6, w: 1280, h: 720, seq: 1), now: 0)
        var d = policy.consume(header(2, w: 1920, h: 1088, seq: 2), now: 0.1)
        XCTAssertEqual(d, .init(decode: false, resetDecoder: false, requestKeyframe: true))
        XCTAssertEqual(policy.resetCount, 1)
        d = policy.consume(header(6, w: 1920, h: 1088, seq: 3), now: 0.2)
        XCTAssertEqual(d, .init(decode: true, resetDecoder: true, requestKeyframe: false))
        XCTAssertEqual(policy.lastWidth, 1920)
        XCTAssertEqual(policy.lastHeight, 1088)
    }

    func testDecoderFailure() {
        var policy = VideoFramePolicy()
        _ = policy.consume(header(6, seq: 1), now: 0)
        XCTAssertTrue(policy.decoderFailed(now: 0.1))
        XCTAssertTrue(policy.waitingForIDR)
        XCTAssertEqual(policy.resetCount, 1)
        let d = policy.consume(header(6, seq: 2), now: 0.2)
        XCTAssertEqual(d, .init(decode: true, resetDecoder: true, requestKeyframe: false))
    }

    func testBacklogResets() {
        var policy = VideoFramePolicy()
        _ = policy.consume(header(6, seq: 1), now: 0)
        var d = policy.consume(header(2, seq: 2), now: 0.1, queuedFrames: 31)
        XCTAssertFalse(d.decode)
        XCTAssertEqual(policy.resetCount, 1)
        _ = policy.consume(header(6, seq: 3), now: 0.2)
        d = policy.consume(header(2, seq: 4), now: 0.3, queuedFrames: 30)
        XCTAssertTrue(d.decode)
        d = policy.consume(header(2, seq: 5), now: 0.4, oldestAge: 0.6)
        XCTAssertFalse(d.decode)
        XCTAssertEqual(policy.resetCount, 2)
        _ = policy.consume(header(6, seq: 6), now: 0.5)
        d = policy.consume(header(2, seq: 7), now: 0.6, oldestAge: 0.5)
        XCTAssertTrue(d.decode)
    }

    func testKeyframeThrottle() {
        var policy = VideoFramePolicy()
        var d = policy.consume(header(2, seq: 0), now: 0)
        XCTAssertTrue(d.requestKeyframe)
        d = policy.consume(header(2, seq: 1), now: 0.1)
        XCTAssertFalse(d.requestKeyframe)
        d = policy.consume(header(2, seq: 2), now: 0.29)
        XCTAssertFalse(d.requestKeyframe)
        d = policy.consume(header(2, seq: 3), now: 0.3)
        XCTAssertTrue(d.requestKeyframe)
    }

    func testReset() {
        var policy = VideoFramePolicy()
        _ = policy.consume(header(6, seq: 1), now: 0)
        _ = policy.consume(header(2, seq: 5), now: 0.1)
        policy.reset()
        XCTAssertTrue(policy.waitingForIDR)
        XCTAssertEqual(policy.resetCount, 0)
        XCTAssertEqual(policy.droppedCount, 0)
        XCTAssertNil(policy.lastSequence)
        XCTAssertNil(policy.lastWidth)
    }
}
