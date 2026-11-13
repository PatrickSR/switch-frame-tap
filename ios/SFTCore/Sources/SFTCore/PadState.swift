// SPDX-License-Identifier: GPL-2.0-only
import Foundation

public struct PadButtons: OptionSet, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let a = PadButtons(rawValue: 1 << 0)
    public static let b = PadButtons(rawValue: 1 << 1)
    public static let x = PadButtons(rawValue: 1 << 2)
    public static let y = PadButtons(rawValue: 1 << 3)
    public static let l3 = PadButtons(rawValue: 1 << 4)
    public static let r3 = PadButtons(rawValue: 1 << 5)
    public static let l = PadButtons(rawValue: 1 << 6)
    public static let r = PadButtons(rawValue: 1 << 7)
    public static let zl = PadButtons(rawValue: 1 << 8)
    public static let zr = PadButtons(rawValue: 1 << 9)
    public static let plus = PadButtons(rawValue: 1 << 10)
    public static let minus = PadButtons(rawValue: 1 << 11)
    public static let left = PadButtons(rawValue: 1 << 12)
    public static let up = PadButtons(rawValue: 1 << 13)
    public static let right = PadButtons(rawValue: 1 << 14)
    public static let down = PadButtons(rawValue: 1 << 15)
    public static let home = PadButtons(rawValue: 1 << 18)
    public static let capture = PadButtons(rawValue: 1 << 19)
}

public struct PadState: Equatable, Sendable {
    public var buttons: PadButtons
    public var lx: Int32
    public var ly: Int32
    public var rx: Int32
    public var ry: Int32

    public init(buttons: PadButtons = [], lx: Int32 = 0, ly: Int32 = 0, rx: Int32 = 0, ry: Int32 = 0) {
        self.buttons = buttons
        self.lx = lx
        self.ly = ly
        self.rx = rx
        self.ry = ry
    }

    public static let stickRange: Double = 32767
    public static let stickDeadZone = 0.08

    public static func normalizedStick(x: Double, y: Double) -> (Int32, Int32) {
        let full = stickRange
        let sx = x * full
        let sy = -y * full
        let m = (sx * sx + sy * sy).squareRoot()
        let dead = stickDeadZone * full
        guard m.isFinite, m > dead else { return (0, 0) }
        var k = (m - dead) / (full - dead) / m * full
        if m * k > full { k = full / m }
        let ox = Swift.min(full, Swift.max(-full, sx * k))
        let oy = Swift.min(full, Swift.max(-full, sy * k))
        return (Int32(ox), Int32(oy))
    }
}

public struct PadSendSchedule: Sendable {
    public var interval: TimeInterval
    private var lastState: PadState?
    private var lastSentAt: TimeInterval = 0

    public init(interval: TimeInterval = 0.1) {
        self.interval = interval
    }

    public mutating func shouldSend(state: PadState, now: TimeInterval) -> Bool {
        if let last = lastState, last == state {
            guard now - lastSentAt >= interval else { return false }
            lastSentAt = now
            return true
        }
        lastState = state
        lastSentAt = now
        return true
    }

    public mutating func reset() {
        lastState = nil
        lastSentAt = 0
    }
}
