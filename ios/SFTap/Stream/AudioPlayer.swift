// SPDX-License-Identifier: GPL-2.0-only
import AVFoundation
import Foundation
import os
import SFTCore

final class AudioPlayer: @unchecked Sendable {
    struct Snapshot {
        var bufferedMs = 0.0
        var underruns = 0
        var droppedMs = 0.0
    }

    private let lock = OSAllocatedUnfairLock()
    private let jitter = AudioJitterBuffer()
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var muted = false
    private var preset: AudioJitterBuffer.Preset = .standard
    private var observers: [NSObjectProtocol] = []
    private var wantsPlayback = false
    private var interrupted = false

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var format: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    }

    func append(_ data: Data) {
        lock.withLock {
            jitter.append(data)
        }
    }

    func start() {
        wantsPlayback = true
        guard !interrupted else { return }
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .default)
        try? audioSession.setPreferredSampleRate(48000)
        try? audioSession.setPreferredIOBufferDuration(0.005)
        try? audioSession.setActive(true)
        if engine == nil { buildEngine() }
        if let engine, !engine.isRunning {
            try? engine.start()
        }
        installObservers()
    }

    func stop() {
        wantsPlayback = false
        engine?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func clearBuffer() {
        lock.withLock { jitter.clear() }
    }

    func setMuted(_ muted: Bool) {
        self.muted = muted
        engine?.mainMixerNode.outputVolume = muted ? 0 : 1
    }

    func setPreset(_ rawValue: Int) {
        guard let value = AudioJitterBuffer.Preset(rawValue: rawValue) else { return }
        preset = value
        lock.withLock { jitter.preset = value }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                bufferedMs: Double(jitter.bufferedFrames) / 48,
                underruns: jitter.underruns,
                droppedMs: Double(jitter.droppedFrames) / 48
            )
        }
    }

    private func buildEngine() {
        let engine = AVAudioEngine()
        let source = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, buffers in
            self?.render(frameCount: frameCount, buffers: buffers) ?? noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
        engine.prepare()
        self.engine = engine
        self.source = source
    }

    private func render(frameCount: AVAudioFrameCount, buffers: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        let frames = Int(frameCount)
        let produced = lock.withLockIfAvailable { () -> Bool in
            guard list.count >= 2,
                  let leftData = list[0].mData,
                  let rightData = list[1].mData else { return false }
            let left = UnsafeMutableBufferPointer(
                start: leftData.assumingMemoryBound(to: Float.self),
                count: frames
            )
            let right = UnsafeMutableBufferPointer(
                start: rightData.assumingMemoryBound(to: Float.self),
                count: frames
            )
            _ = jitter.read(into: left, right, frames: frames)
            return true
        }
        if produced != true {
            for buffer in list {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
        }
        return noErr
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self.interrupted = true
                self.engine?.stop()
                self.clearBuffer()
            } else {
                self.interrupted = false
                let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                if self.wantsPlayback,
                   AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    self.lock.withLock { self.jitter.clear() }
                    try? AVAudioSession.sharedInstance().setActive(true)
                    if let engine = self.engine, !engine.isRunning {
                        try? engine.start()
                    }
                }
            }
        })
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, self.wantsPlayback, !self.interrupted,
                  let engine = self.engine, note.object as? AVAudioEngine === engine else { return }
            if !engine.isRunning { try? engine.start() }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.engine?.stop()
            self.engine = nil
            self.source = nil
            self.lock.withLock { self.jitter.clear() }
            if self.wantsPlayback { self.start() }
        })
    }
}
