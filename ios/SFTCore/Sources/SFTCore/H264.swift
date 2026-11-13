// SPDX-License-Identifier: GPL-2.0-only
import Foundation

public enum H264Error: Error, Equatable {
    case empty
    case truncatedNALUnit
    case missingParameterSets
    case noDecodableNALUnits
}

public enum H264 {
    public struct NALUnit: Equatable, Sendable {
        public let type: UInt8
        public let data: Data
        public init(type: UInt8, data: Data) {
            self.type = type
            self.data = data
        }
    }

    public static func nalUnits(in data: Data) -> [NALUnit] {
        (try? scan(data, strict: false)) ?? []
    }

    public static func parameterSets(in data: Data) throws -> (sps: Data, pps: Data) {
        var sps: Data?
        var pps: Data?
        for unit in try scan(data, strict: false) {
            if unit.type == 7 { sps = unit.data }
            if unit.type == 8 { pps = unit.data }
        }
        guard let sps, let pps else { throw H264Error.missingParameterSets }
        return (sps, pps)
    }

    public static func isIDR(_ data: Data) -> Bool {
        nalUnits(in: data).contains { $0.type == 5 }
    }

    public static func accessUnit(from data: Data) throws -> Data {
        let units = try scan(data, strict: true)
        var out = Data()
        var kept = 0
        for unit in units where unit.type != 7 && unit.type != 8 && unit.type != 9 {
            let n = UInt32(unit.data.count)
            out.append(contentsOf: [
                UInt8(truncatingIfNeeded: n >> 24),
                UInt8(truncatingIfNeeded: n >> 16),
                UInt8(truncatingIfNeeded: n >> 8),
                UInt8(truncatingIfNeeded: n),
            ])
            out.append(unit.data)
            kept += 1
        }
        guard kept > 0 else {
            throw units.isEmpty ? H264Error.empty : H264Error.noDecodableNALUnits
        }
        return out
    }

    static func startCodeLength(_ d: Data, at i: Int) -> Int {
        let s = d.startIndex
        guard i + 2 < d.count, d[s + i] == 0, d[s + i + 1] == 0 else { return 0 }
        if d[s + i + 2] == 1 { return 3 }
        return i + 3 < d.count && d[s + i + 2] == 0 && d[s + i + 3] == 1 ? 4 : 0
    }

    static func scan(_ data: Data, strict: Bool) throws -> [NALUnit] {
        var units: [NALUnit] = []
        var i = 0
        while i < data.count {
            let prefix = startCodeLength(data, at: i)
            if prefix == 0 {
                i += 1
                continue
            }
            let nal = i + prefix
            if nal >= data.count {
                if strict { throw H264Error.truncatedNALUnit }
                break
            }
            var end = nal + 1
            while end < data.count && startCodeLength(data, at: end) == 0 { end += 1 }
            let payload = data.subdata(in: data.startIndex + nal ..< data.startIndex + end)
            units.append(NALUnit(type: payload[payload.startIndex] & 0x1F, data: payload))
            i = end
        }
        return units
    }
}
