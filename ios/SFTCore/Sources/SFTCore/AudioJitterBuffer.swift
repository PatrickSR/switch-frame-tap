// SPDX-License-Identifier: GPL-2.0-only
import Foundation

public final class AudioJitterBuffer {
    public enum Preset: Int, CaseIterable, Sendable {
        case low
        case standard
        case stable

        public var targetFrames: Int {
            switch self {
            case .low: return 48000 * 40 / 1000
            case .standard: return 48000 * 80 / 1000
            case .stable: return 48000 * 150 / 1000
            }
        }
    }

    public static let capacityFrames = 48000
    public static let overflowSlackFrames = 4800

    public private(set) var underruns = 0
    public private(set) var droppedFrames = 0
    public private(set) var bufferedFrames = 0
    public private(set) var isPlaying = false

    public var preset: Preset {
        didSet { normalize() }
    }
    public var targetFrames: Int { preset.targetFrames }

    private var ring: [Int16]
    private var readPos = 0
    private var writePos = 0

    public init(preset: Preset = .standard) {
        self.preset = preset
        ring = [Int16](repeating: 0, count: Self.capacityFrames * 2)
    }

    public func append(_ pcm: Data) {
        var frames = pcm.count / 4
        guard frames > 0 else { return }
        var firstByte = 0
        if frames > Self.capacityFrames {
            firstByte = (frames - Self.capacityFrames) * 4
            frames = Self.capacityFrames
        }
        let capacityOverflow = bufferedFrames + frames - Self.capacityFrames
        if capacityOverflow > 0 { discard(capacityOverflow) }
        let base = pcm.startIndex
        for i in 0 ..< frames {
            let s = base + firstByte + i * 4
            ring[writePos * 2] = Int16(bitPattern: UInt16(pcm[s]) | UInt16(pcm[s + 1]) << 8)
            ring[writePos * 2 + 1] = Int16(bitPattern: UInt16(pcm[s + 2]) | UInt16(pcm[s + 3]) << 8)
            writePos = (writePos + 1) % Self.capacityFrames
        }
        bufferedFrames += frames
        applyWaterLevel()
        if bufferedFrames >= targetFrames { isPlaying = true }
    }

    public func read(
        into left: UnsafeMutableBufferPointer<Float>,
        _ right: UnsafeMutableBufferPointer<Float>,
        frames: Int
    ) -> Int {
        let n = Swift.min(frames, Swift.min(left.count, right.count))
        var produced = 0
        if isPlaying {
            let available = Swift.min(n, bufferedFrames)
            for i in 0 ..< available {
                left[i] = Float(ring[readPos * 2]) / 32768
                right[i] = Float(ring[readPos * 2 + 1]) / 32768
                readPos = (readPos + 1) % Self.capacityFrames
            }
            bufferedFrames -= available
            produced = available
            if available < n {
                underruns += 1
                isPlaying = false
            }
        }
        for i in produced ..< n {
            left[i] = 0
            right[i] = 0
        }
        return n
    }

    public func read(_ frames: Int) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                _ = read(into: l, r, frames: frames)
            }
        }
        return (left, right)
    }

    public func clear() {
        bufferedFrames = 0
        readPos = 0
        writePos = 0
        isPlaying = false
    }

    private func discard(_ frames: Int) {
        readPos = (readPos + frames) % Self.capacityFrames
        bufferedFrames -= frames
        droppedFrames += frames
    }

    private func applyWaterLevel() {
        if bufferedFrames > targetFrames + Self.overflowSlackFrames {
            discard(bufferedFrames - targetFrames)
        }
    }

    private func normalize() {
        applyWaterLevel()
        if bufferedFrames >= targetFrames { isPlaying = true }
    }
}
