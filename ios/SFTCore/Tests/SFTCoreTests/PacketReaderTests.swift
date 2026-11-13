// SPDX-License-Identifier: GPL-2.0-only
import XCTest
@testable import SFTCore

final class PacketReaderTests: XCTestCase {
    let audio = Data([1, 2, 3, 4, 5, 6, 7, 8])
    let nal = Data([0, 0, 0, 1, 0x67, 0x64, 0, 0, 1, 0x68, 0x12, 0, 0, 1, 0x65, 9])

    func testAudioAndVideoPackets() throws {
        var stream = wire(flags: 8, width: 48000, height: 2, seq: 1, payload: audio)
        stream.append(wire(flags: 6, width: 1280, height: 720, seq: 0xFFFF_FFFF, payload: nal))
        let packets = try PacketReader().feed(stream, receivedAt: 1)
        XCTAssertEqual(packets.count, 2)
        XCTAssertTrue(packets[0].isAudio)
        XCTAssertEqual(packets[0].payload, audio)
        XCTAssertEqual(packets[0].sequence, 1)
        XCTAssertTrue(packets[1].isVideo)
        XCTAssertTrue(packets[1].isKeyFrame)
        XCTAssertEqual(packets[1].sequence, 0xFFFF_FFFF)
        XCTAssertEqual(packets[1].consoleAgeMicros, 25000)
        XCTAssertEqual(packets[1].payload, nal)
    }

    func testChunkedFeedsAgree() throws {
        var stream = wire(flags: 8, width: 48000, height: 2, seq: 1, payload: audio)
        stream.append(wire(flags: 0))
        stream.append(wire(flags: 6, width: 1280, height: 720, seq: 2, payload: nal))
        let whole = try PacketReader().feed(stream, receivedAt: 1)
        for size in [1, 7, 97] {
            let packets = try feedChunked(PacketReader(), stream, chunk: size, at: 1)
            XCTAssertEqual(packets.count, whole.count, "chunk \(size)")
            for (a, b) in zip(packets, whole) {
                XCTAssertEqual(a.header, b.header)
                XCTAssertEqual(a.payload, b.payload)
                XCTAssertEqual(a.receivedAt, b.receivedAt)
            }
        }
    }

    func testEmptyKeepalivesSkipped() throws {
        var stream = wire(flags: 0)
        stream.append(wire(flags: 0, width: 999, height: 999))
        stream.append(wire(flags: 8, width: 48000, height: 2, seq: 2, payload: audio))
        let packets = try PacketReader().feed(stream, receivedAt: 0)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].sequence, 2)
    }

    func testTruncatedPayloadWaits() throws {
        let reader = PacketReader()
        let stream = wire(flags: 6, width: 1280, height: 720, seq: 1, payload: nal)
        let header = stream.prefix(32)
        XCTAssertEqual(try reader.feed(Data(header), receivedAt: 0).count, 0)
        XCTAssertEqual(try reader.feed(stream.subdata(in: 32 ..< 37), receivedAt: 0).count, 0)
        let rest = try reader.feed(stream.subdata(in: 37 ..< stream.count), receivedAt: 0)
        XCTAssertEqual(rest.count, 1)
        XCTAssertEqual(rest[0].payload, nal)
    }

    func testTruncatedHeaderWaits() throws {
        let reader = PacketReader()
        let stream = wire(flags: 8, width: 48000, height: 2, seq: 3, payload: audio)
        XCTAssertEqual(try reader.feed(stream.prefix(20), receivedAt: 0).count, 0)
        let packets = try reader.feed(stream.subdata(in: 20 ..< stream.count), receivedAt: 0)
        XCTAssertEqual(packets.count, 1)
        XCTAssertTrue(packets[0].isAudio)
    }

    func testHeaderArrivalTimestamp() throws {
        let reader = PacketReader()
        let stream = wire(flags: 6, width: 1280, height: 720, seq: 1, payload: nal)
        try reader.feed(stream.prefix(20), receivedAt: 50)
        try reader.feed(stream.subdata(in: 20 ..< 32), receivedAt: 60)
        let packets = try reader.feed(stream.subdata(in: 32 ..< stream.count), receivedAt: 70)
        XCTAssertEqual(packets[0].receivedAt, 60)
    }

    func testBadMagicAndVersion() throws {
        var bad = wire(flags: 6, width: 1280, height: 720, payload: nal)
        bad[0] = 0
        XCTAssertThrowsError(try PacketReader().feed(bad, receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .badMagic)
        }
        var old = wire(flags: 6, width: 1280, height: 720, payload: nal)
        old[4] = 1
        XCTAssertThrowsError(try PacketReader().feed(old, receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .unsupportedVersion(1))
        }
        XCTAssertThrowsError(try SFTRHeader(Data(repeating: 0, count: 10))) {
            XCTAssertEqual($0 as? SFTRError, .truncatedHeader)
        }
    }

    func testVideoBounds() throws {
        for (w, h, n) in [(UInt32(16), UInt32(16), UInt32(1)), (1920, 1088, SFTRHeader.maxVideoPayload)] {
            let packets = try PacketReader().feed(wire(flags: 2, width: w, height: h, payload: Data(repeating: 1, count: Int(n))), receivedAt: 0)
            XCTAssertEqual(packets.count, 1, "w\(w) h\(h) n\(n)")
        }
        for (w, h, n) in [
            (UInt32(15), UInt32(720), UInt32(1)),
            (14, 720, 1),
            (17, 720, 1),
            (1922, 720, 1),
            (1280, 15, 1),
            (1280, 17, 1),
            (1280, 1090, 1),
            (1280, 720, 0),
            (1280, 720, SFTRHeader.maxVideoPayload + 1),
            (1280, 720, 0xFFFF_FFFF),
        ] {
            XCTAssertThrowsError(
                try PacketReader().feed(wire(flags: 2, width: w, height: h, n: n, payload: nal), receivedAt: 0),
                "w\(w) h\(h) n\(n)"
            ) { XCTAssertEqual($0 as? SFTRError, .invalidVideoPacket) }
        }
    }

    func testVideoFlagCombinations() throws {
        let cropped = try PacketReader().feed(wire(flags: 2 | 4 | 32 | 64, width: 1920, height: 1080, seq: 5, payload: nal), receivedAt: 0)
        XCTAssertEqual(cropped.count, 1)
        XCTAssertTrue(cropped[0].isKeyFrame)
        XCTAssertThrowsError(try PacketReader().feed(wire(flags: 4, width: 1280, height: 720, payload: nal), receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .invalidVideoPacket)
        }
    }

    func testAudioValidation() throws {
        XCTAssertThrowsError(try PacketReader().feed(wire(flags: 8, width: 44100, height: 2, payload: audio), receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .invalidAudioPacket)
        }
        XCTAssertThrowsError(try PacketReader().feed(wire(flags: 8, width: 48000, height: 2, payload: Data([1, 2, 3])), receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .invalidAudioPacket)
        }
        XCTAssertThrowsError(try PacketReader().feed(wire(flags: 8, width: 48000, height: 1, payload: audio), receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .invalidAudioPacket)
        }
        XCTAssertThrowsError(try PacketReader().feed(wire(flags: 8, width: 48000, height: 2, n: 0, payload: audio), receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .invalidAudioPacket)
        }
        XCTAssertThrowsError(try PacketReader().feed(wire(flags: 8, width: 48000, height: 2, n: 65537, payload: audio), receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .invalidAudioPacket)
        }
        XCTAssertThrowsError(try PacketReader().feed(wire(flags: 8 | 32, width: 48000, height: 2, payload: audio), receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .invalidAudioPacket)
        }
        XCTAssertThrowsError(try PacketReader().feed(wire(flags: 10, width: 1280, height: 720, payload: nal), receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .invalidAudioPacket)
        }
        let ok = try PacketReader().feed(wire(flags: 8, width: 48000, height: 2, payload: Data(repeating: 0, count: 65536)), receivedAt: 0)
        XCTAssertEqual(ok.count, 1)
    }

    func testStatusValidation() throws {
        let status = wire(flags: 24, payload: Data(repeating: 0, count: 8))
        XCTAssertThrowsError(try PacketReader().feed(wire(flags: 16, payload: Data(repeating: 0, count: 8)), receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .invalidStatusPacket)
        }
        XCTAssertThrowsError(try PacketReader().feed(wire(flags: 18, payload: Data(repeating: 0, count: 8)), receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .invalidStatusPacket)
        }
        XCTAssertThrowsError(try PacketReader().feed(wire(flags: 24, payload: Data(repeating: 0, count: 4)), receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .invalidStatusPacket)
        }
        XCTAssertThrowsError(try PacketReader().feed(wire(flags: 24, n: 4097, payload: Data(repeating: 0, count: 8)), receivedAt: 0)) {
            XCTAssertEqual($0 as? SFTRError, .invalidStatusPacket)
        }
        XCTAssertEqual(try PacketReader().feed(status, receivedAt: 0).count, 1)
        XCTAssertEqual(try PacketReader().feed(wire(flags: 24, payload: Data(repeating: 0, count: 4096)), receivedAt: 0).count, 1)
    }

    func testUnknownFlagsRejected() throws {
        for flags: UInt16 in [1, 3, 5, 127] {
            XCTAssertThrowsError(
                try PacketReader().feed(wire(flags: flags, width: 1280, height: 720, payload: nal), receivedAt: 0),
                "flags \(flags)"
            ) { XCTAssertEqual($0 as? SFTRError, .unsupportedFlags(flags)) }
        }
    }

    func testInputCapability() throws {
        let reader = PacketReader()
        var seen: [Bool] = []
        reader.onInputCapability = { seen.append($0) }
        try reader.feed(wire(flags: 2 | 128, width: 1280, height: 720, seq: 8, payload: nal), receivedAt: 0)
        XCTAssertEqual(seen, [true])
        try reader.feed(wire(flags: 2 | 4, width: 1280, height: 720, seq: 9, payload: nal), receivedAt: 0)
        XCTAssertEqual(seen, [true, false])
        try reader.feed(wire(flags: 24 | 128, seq: 3, payload: Data(repeating: 0, count: 8)), receivedAt: 0)
        XCTAssertEqual(seen, [true, false, true])
        try reader.feed(wire(flags: 8, width: 48000, height: 2, seq: 5, payload: audio), receivedAt: 0)
        XCTAssertEqual(seen, [true, false, true])
        XCTAssertEqual(reader.inputCapability, true)
    }

    func testKeepaliveWithInputBitReportsAndSkips() throws {
        let reader = PacketReader()
        var seen: [Bool] = []
        reader.onInputCapability = { seen.append($0) }
        var stream = wire(flags: 128)
        stream.append(wire(flags: 8, width: 48000, height: 2, seq: 4, payload: audio))
        let packets = try reader.feed(stream, receivedAt: 0)
        XCTAssertEqual(seen, [true])
        XCTAssertEqual(reader.inputCapability, true)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].sequence, 4)
    }

    func testPlainAudioDoesNotRevokeCapability() throws {
        let reader = PacketReader()
        var calls = 0
        reader.onInputCapability = { _ in calls += 1 }
        try reader.feed(wire(flags: 2 | 128, width: 1280, height: 720, seq: 1, payload: nal), receivedAt: 0)
        XCTAssertEqual(reader.inputCapability, true)
        try reader.feed(wire(flags: 8 | 128, width: 48000, height: 2, seq: 2, payload: audio), receivedAt: 0)
        XCTAssertEqual(reader.inputCapability, true)
        XCTAssertEqual(calls, 1)
    }

    func testFlag128AcceptedOnVideoAndStatus() throws {
        let video = try PacketReader().feed(wire(flags: 2 | 4 | 128, width: 1280, height: 720, seq: 7, payload: nal), receivedAt: 0)
        XCTAssertEqual(video.count, 1)
        XCTAssertTrue(video[0].isKeyFrame)
        XCTAssertEqual(video[0].payload, nal)
        let status = try PacketReader().feed(wire(flags: 24 | 128, seq: 3, payload: Data(repeating: 0, count: 192)), receivedAt: 0)
        XCTAssertEqual(status.count, 1)
        XCTAssertTrue(status[0].isStatus)
    }

    func testReset() throws {
        let reader = PacketReader()
        try reader.feed(Data([1, 2, 3]), receivedAt: 0)
        reader.reset()
        XCTAssertNil(reader.inputCapability)
        let packets = try reader.feed(wire(flags: 8, width: 48000, height: 2, seq: 1, payload: audio), receivedAt: 0)
        XCTAssertEqual(packets.count, 1)
    }
}
