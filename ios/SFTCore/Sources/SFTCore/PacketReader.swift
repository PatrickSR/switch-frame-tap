// SPDX-License-Identifier: GPL-2.0-only
import Foundation

public enum MonotonicClock {
    public static func now() -> TimeInterval {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        return TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1_000_000_000
    }
}

public final class PacketReader {
    public private(set) var inputCapability: Bool?
    public var onInputCapability: ((Bool) -> Void)?

    private var buffer = Data()
    private var consumed = 0
    private var pendingHeader: SFTRHeader?
    private var pendingArrival: TimeInterval = 0

    public init() {}

    public func reset() {
        buffer.removeAll(keepingCapacity: true)
        consumed = 0
        pendingHeader = nil
        inputCapability = nil
    }

    @discardableResult
    public func feed(_ data: Data, receivedAt: TimeInterval = MonotonicClock.now()) throws -> [Packet] {
        buffer.append(contentsOf: data)
        var packets: [Packet] = []
        while true {
            if let header = pendingHeader {
                let need = Int(header.payloadLength)
                guard buffer.count - consumed >= need else { break }
                let payload = buffer.subdata(in: consumed ..< consumed + need)
                packets.append(Packet(header: header, payload: payload, receivedAt: pendingArrival))
                consumed += need
                pendingHeader = nil
            } else {
                guard buffer.count - consumed >= SFTRHeader.size else { break }
                let header = try SFTRHeader(buffer.subdata(in: consumed ..< consumed + SFTRHeader.size))
                if let takes = header.consoleTakesInput {
                    inputCapability = takes
                    onInputCapability?(takes)
                }
                consumed += SFTRHeader.size
                if header.isEmptyKeepalive { continue }
                try header.validate()
                pendingHeader = header
                pendingArrival = receivedAt
            }
        }
        if consumed > 0 {
            buffer = consumed == buffer.count
                ? Data()
                : buffer.subdata(in: consumed ..< buffer.count)
            consumed = 0
        }
        return packets
    }
}
