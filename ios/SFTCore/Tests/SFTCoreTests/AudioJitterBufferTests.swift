// SPDX-License-Identifier: GPL-2.0-only
import XCTest
@testable import SFTCore

final class AudioJitterBufferTests: XCTestCase {
    func testPresetTargets() {
        XCTAssertEqual(AudioJitterBuffer.Preset.low.targetFrames, 1920)
        XCTAssertEqual(AudioJitterBuffer.Preset.standard.targetFrames, 3840)
        XCTAssertEqual(AudioJitterBuffer.Preset.stable.targetFrames, 7200)
        XCTAssertEqual(AudioJitterBuffer(preset: .low).targetFrames, 1920)
    }

    func testPrefillThenPlay() {
        let buffer = AudioJitterBuffer(preset: .standard)
        buffer.append(pcm(1000) { _ in (100, -100) })
        XCTAssertFalse(buffer.isPlaying)
        var out = buffer.read(200)
        XCTAssertTrue(out.left.allSatisfy { $0 == 0 })
        buffer.append(pcm(3000) { _ in (100, -100) })
        XCTAssertTrue(buffer.isPlaying)
        out = buffer.read(100)
        XCTAssertTrue(out.left.allSatisfy { $0 == Float(100) / 32768 })
        XCTAssertTrue(out.right.allSatisfy { $0 == Float(-100) / 32768 })
    }

    func testInterleavedConversion() {
        let buffer = AudioJitterBuffer(preset: .low)
        buffer.append(pcm(2000) { i in (Int16(i), Int16(-i)) })
        let out = buffer.read(4)
        XCTAssertEqual(out.left[0], 0)
        XCTAssertEqual(out.left[1], Float(1) / 32768)
        XCTAssertEqual(out.right[3], Float(-3) / 32768)
    }

    func testUnderrunWritesSilenceAndReentersPrefill() {
        let buffer = AudioJitterBuffer(preset: .low)
        buffer.append(pcm(1920) { _ in (1000, 1000) })
        XCTAssertTrue(buffer.isPlaying)
        let out = buffer.read(2000)
        XCTAssertEqual(out.left[0], Float(1000) / 32768)
        XCTAssertEqual(out.left[1919], Float(1000) / 32768)
        XCTAssertEqual(out.left[1920], 0)
        XCTAssertEqual(out.left[1999], 0)
        XCTAssertEqual(buffer.underruns, 1)
        XCTAssertFalse(buffer.isPlaying)
        XCTAssertEqual(buffer.bufferedFrames, 0)
        let again = buffer.read(10)
        XCTAssertTrue(again.left.allSatisfy { $0 == 0 })
        XCTAssertEqual(buffer.underruns, 1)
    }

    func testOverflowDropsOldestToTarget() {
        let buffer = AudioJitterBuffer(preset: .low)
        buffer.append(pcm(7220) { i in (Int16(i), 0) })
        XCTAssertEqual(buffer.bufferedFrames, 1920)
        XCTAssertEqual(buffer.droppedFrames, 5300)
        let out = buffer.read(1)
        XCTAssertEqual(out.left[0], Float(5300) / 32768)
    }

    func testHardCapacity() {
        let buffer = AudioJitterBuffer(preset: .stable)
        buffer.append(pcm(49000) { _ in (1, 1) })
        XCTAssertLessThanOrEqual(buffer.bufferedFrames, AudioJitterBuffer.capacityFrames)
        XCTAssertEqual(buffer.bufferedFrames, 7200)
        XCTAssertEqual(buffer.droppedFrames, 48000 - 7200)
    }

    func testTargetChangeHonored() {
        let buffer = AudioJitterBuffer(preset: .stable)
        buffer.append(pcm(12000) { _ in (1, 1) })
        XCTAssertEqual(buffer.bufferedFrames, 12000)
        buffer.preset = .low
        XCTAssertEqual(buffer.bufferedFrames, 1920)
        XCTAssertEqual(buffer.droppedFrames, 12000 - 1920)
    }

    func testPrefillHonorsNewTarget() {
        let buffer = AudioJitterBuffer(preset: .low)
        buffer.append(pcm(1920) { _ in (1, 1) })
        XCTAssertTrue(buffer.isPlaying)
        buffer.clear()
        buffer.preset = .standard
        buffer.append(pcm(2000) { _ in (1, 1) })
        XCTAssertFalse(buffer.isPlaying)
    }

    func testClear() {
        let buffer = AudioJitterBuffer()
        buffer.append(pcm(4000) { _ in (5, 5) })
        buffer.clear()
        XCTAssertEqual(buffer.bufferedFrames, 0)
        XCTAssertFalse(buffer.isPlaying)
        let out = buffer.read(10)
        XCTAssertTrue(out.left.allSatisfy { $0 == 0 })
    }

    func testReadIntoBuffers() {
        let buffer = AudioJitterBuffer(preset: .low)
        buffer.append(pcm(2000) { _ in (327, -327) })
        var left = [Float](repeating: 0, count: 8)
        var right = [Float](repeating: 0, count: 8)
        let n = left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                buffer.read(into: l, r, frames: 8)
            }
        }
        XCTAssertEqual(n, 8)
        XCTAssertEqual(left[7], Float(327) / 32768)
        XCTAssertEqual(right[7], Float(-327) / 32768)
    }
}
