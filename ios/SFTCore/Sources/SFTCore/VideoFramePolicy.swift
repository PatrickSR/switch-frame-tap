// SPDX-License-Identifier: GPL-2.0-only
import Foundation

public struct VideoFramePolicy: Sendable {
    public struct Decision: Equatable, Sendable {
        public var decode: Bool
        public var resetDecoder: Bool
        public var requestKeyframe: Bool

        public init(decode: Bool, resetDecoder: Bool, requestKeyframe: Bool) {
            self.decode = decode
            self.resetDecoder = resetDecoder
            self.requestKeyframe = requestKeyframe
        }
    }

    public static let keyframeRequestInterval: TimeInterval = 0.3
    public static let maxQueuedFrames = 30
    public static let maxOldestAge: TimeInterval = 0.5

    public private(set) var waitingForIDR = true
    public private(set) var resetCount = 0
    public private(set) var droppedCount = 0
    public private(set) var lastSequence: UInt32?
    public private(set) var lastWidth: UInt32?
    public private(set) var lastHeight: UInt32?
    private var lastKeyframeRequestAt: TimeInterval?

    public init() {}

    public mutating func reset() {
        self = VideoFramePolicy()
    }

    public mutating func decoderFailed(now: TimeInterval) -> Bool {
        if !waitingForIDR { resetCount += 1 }
        waitingForIDR = true
        return keyframeThrottle(now)
    }

    public mutating func consume(
        _ header: SFTRHeader,
        now: TimeInterval,
        queuedFrames: Int = 0,
        oldestAge: TimeInterval = 0
    ) -> Decision {
        if waitingForIDR {
            if header.isKeyFrame { return recover(header) }
            droppedCount += 1
            return Decision(decode: false, resetDecoder: false, requestKeyframe: keyframeThrottle(now))
        }
        let gap = lastSequence.map { header.sequence != $0 &+ 1 } ?? false
        let resized = lastWidth != nil && (header.width != lastWidth || header.height != lastHeight)
        let backlog = queuedFrames > Self.maxQueuedFrames || oldestAge > Self.maxOldestAge
        if gap || resized || backlog {
            waitingForIDR = true
            resetCount += 1
            if header.isKeyFrame { return recover(header) }
            droppedCount += 1
            return Decision(decode: false, resetDecoder: false, requestKeyframe: keyframeThrottle(now))
        }
        lastSequence = header.sequence
        return Decision(decode: true, resetDecoder: false, requestKeyframe: false)
    }

    private mutating func recover(_ header: SFTRHeader) -> Decision {
        waitingForIDR = false
        lastSequence = header.sequence
        lastWidth = header.width
        lastHeight = header.height
        return Decision(decode: true, resetDecoder: true, requestKeyframe: false)
    }

    private mutating func keyframeThrottle(_ now: TimeInterval) -> Bool {
        if let last = lastKeyframeRequestAt, now - last < Self.keyframeRequestInterval {
            return false
        }
        lastKeyframeRequestAt = now
        return true
    }
}
