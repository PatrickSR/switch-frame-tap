// SPDX-License-Identifier: GPL-2.0-only
import Foundation
@testable import SFTCore

func le16(_ v: UInt16) -> [UInt8] {
    [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)]
}

func le32(_ v: UInt32) -> [UInt8] {
    [
        UInt8(truncatingIfNeeded: v),
        UInt8(truncatingIfNeeded: v >> 8),
        UInt8(truncatingIfNeeded: v >> 16),
        UInt8(truncatingIfNeeded: v >> 24),
    ]
}

func wire(
    flags: UInt16,
    width: UInt32 = 0,
    height: UInt32 = 0,
    age: UInt32 = 25000,
    n: UInt32? = nil,
    crop: UInt32 = 0,
    seq: UInt32 = 0,
    payload: Data = Data()
) -> Data {
    var h = Data()
    h.append(contentsOf: le32(0x5254_4653))
    h.append(contentsOf: le16(2))
    h.append(contentsOf: le16(flags))
    h.append(contentsOf: le32(width))
    h.append(contentsOf: le32(height))
    h.append(contentsOf: le32(age))
    h.append(contentsOf: le32(n ?? UInt32(payload.count)))
    h.append(contentsOf: le32(crop))
    h.append(contentsOf: le32(seq))
    h.append(payload)
    return h
}

func feedChunked(_ reader: PacketReader, _ stream: Data, chunk: Int, at t: TimeInterval = 0) throws -> [Packet] {
    var out: [Packet] = []
    var i = stream.startIndex
    while i < stream.endIndex {
        let j = Swift.min(i + chunk, stream.endIndex)
        out.append(contentsOf: try reader.feed(stream[i ..< j], receivedAt: t))
        i = j
    }
    return out
}

func header(_ flags: UInt16, w: UInt32 = 1280, h: UInt32 = 720, seq: UInt32 = 0) -> SFTRHeader {
    try! SFTRHeader(wire(flags: flags, width: w, height: h, seq: seq, payload: Data([0xAA])))
}

func pcm(_ frames: Int, valueAt: (Int) -> (Int16, Int16)) -> Data {
    var d = Data()
    d.reserveCapacity(frames * 4)
    for i in 0 ..< frames {
        let (l, r) = valueAt(i)
        d.append(contentsOf: le16(UInt16(bitPattern: l)))
        d.append(contentsOf: le16(UInt16(bitPattern: r)))
    }
    return d
}
