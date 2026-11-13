// SPDX-License-Identifier: GPL-2.0-only
import Foundation

public struct PadTransmission {
    public struct Message {
        public let data: Data
        public let droppable: Bool
    }

    public private(set) var active = false
    private var state = PadState()
    private var schedule = PadSendSchedule()
    private var lastSent: PadState?

    public init() {}

    public mutating func setActive(_ value: Bool, now: TimeInterval) -> Message? {
        guard active != value else { return nil }
        active = value
        state = PadState()
        schedule.reset()
        lastSent = nil
        if value { return heartbeat(now: now) }
        return Message(data: ViewerMessages.input(controller: false, state: PadState()), droppable: false)
    }

    public mutating func update(_ value: PadState, now: TimeInterval) -> Message? {
        guard active else { return nil }
        state = value
        return heartbeat(now: now)
    }

    public mutating func heartbeat(now: TimeInterval) -> Message? {
        guard active, schedule.shouldSend(state: state, now: now) else { return nil }
        let message = Message(
            data: ViewerMessages.input(controller: true, state: state),
            droppable: lastSent == state
        )
        lastSent = state
        return message
    }
}
