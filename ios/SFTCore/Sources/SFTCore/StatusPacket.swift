// SPDX-License-Identifier: GPL-2.0-only
import Foundation

public struct StatusPacket: Equatable, Sendable {
    public let reason: UInt32
    public let head: String
    public let detail: String

    public init(_ payload: Data) {
        reason = payload.count >= 8 ? SFTRHeader.u32(payload, at: 4) : 0
        head = Self.cString(payload, offset: 8, max: 64)
        detail = Self.cString(payload, offset: 72, max: 120)
    }

    public init(packet: Packet) {
        self.init(packet.payload)
    }

    static func cString(_ d: Data, offset: Int, max: Int) -> String {
        guard offset < d.count else { return "" }
        let start = d.startIndex + offset
        var end = start
        let limit = Swift.min(d.startIndex + d.count, start + max)
        while end < limit && d[end] != 0 { end += 1 }
        return String(decoding: d[start ..< end], as: UTF8.self)
    }
}
