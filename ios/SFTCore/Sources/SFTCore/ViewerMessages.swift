// SPDX-License-Identifier: GPL-2.0-only
import Foundation

public enum ViewerMessages {
    public static let keyframe = Data([0x53, 0x46, 0x54, 0x4B])

    public static func input(controller: Bool, state: PadState) -> Data {
        var m = Data(count: 32)
        m[0] = 0x53
        m[1] = 0x46
        m[2] = 0x54
        m[3] = 0x49
        put32(&m, at: 4, controller ? 1 : 0)
        let buttons = state.buttons.rawValue
        put32(&m, at: 8, UInt32(truncatingIfNeeded: buttons))
        put32(&m, at: 12, UInt32(truncatingIfNeeded: buttons >> 32))
        put32(&m, at: 16, UInt32(bitPattern: state.lx))
        put32(&m, at: 20, UInt32(bitPattern: state.ly))
        put32(&m, at: 24, UInt32(bitPattern: state.rx))
        put32(&m, at: 28, UInt32(bitPattern: state.ry))
        return m
    }

    static func put32(_ d: inout Data, at i: Int, _ v: UInt32) {
        let s = d.startIndex + i
        d[s] = UInt8(truncatingIfNeeded: v)
        d[s + 1] = UInt8(truncatingIfNeeded: v >> 8)
        d[s + 2] = UInt8(truncatingIfNeeded: v >> 16)
        d[s + 3] = UInt8(truncatingIfNeeded: v >> 24)
    }
}
