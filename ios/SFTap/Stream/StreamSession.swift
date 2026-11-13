// SPDX-License-Identifier: GPL-2.0-only
import AVFoundation
import Foundation
import Observation
import SFTCore
import UIKit

@MainActor @Observable
final class StreamSession {
    enum Phase: Equatable {
        case idle
        case connecting(attempt: Int)
        case waitingPicture
        case playing
        case reconnecting(attempt: Int, reason: String)
    }

    struct Snapshot {
        var width = 0
        var height = 0
        var fps = 0.0
        var mbps = 0.0
        var decodeMs = 0.0
        var consoleAgeMs = 0.0
        var displayMs = 0.0
        var resets = 0
        var dropped = 0
        var audioBufferedMs = 0.0
        var audioUnderruns = 0
        var audioDroppedMs = 0.0
        var padState = "未知"
    }

    private(set) var phase: Phase = .idle
    private(set) var lastError: String?
    private(set) var consoleStatus: StatusPacket?
    private(set) var consoleStatusAt: Date?
    private(set) var consoleTakesInput: Bool?
    private(set) var hasRecentPicture = false
    private(set) var stats = Snapshot()

    let displayLayer: AVSampleBufferDisplayLayer
    private let decoder: VideoDecoder
    private let audio = AudioPlayer()
    private let pad: PadSender
    private let netQueue = DispatchQueue(label: "sft.net")
    private let sendBox = SendBox()
    private var generation = 0
    private var failCount = 0
    private var userStopped = true
    private var suspended = false
    private var controlsHidden = false
    private var settings: AppSettings?
    private var host = ""
    private var port = 9950
    private var reconnectItem: DispatchWorkItem?
    private var statsTimer: Timer?
    private var lastTick = MonotonicClock.now()
    private var lastBytes = 0
    private var lastDisplayed = 0

    static let shared = StreamSession()

    init() {
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
        displayLayer = layer
        decoder = VideoDecoder(displayLayer: layer)
        pad = PadSender(queue: netQueue)
        pad.onSend = { [sendBox] data, droppable in
            sendBox.connection?.send(data, droppable: droppable)
        }
        decoder.onKeyframeRequest = { [sendBox, netQueue] in
            netQueue.async {
                sendBox.connection?.send(ViewerMessages.keyframe)
                print("Viewer: SFTK")
            }
        }
        decoder.onFirstFrame = { [weak self] in
            Task { @MainActor in self?.firstFrameDisplayed() }
        }
    }

    func attach(settings: AppSettings) {
        self.settings = settings
        audio.setMuted(settings.muted)
        audio.setPreset(settings.audioPreset)
        let hidden = settings.padHidden
        controlsHidden = hidden
        netQueue.async { [pad] in
            pad.padHidden = hidden
        }
    }

    func start(host: String, port: Int) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
        userStopped = false
        suspended = false
        failCount = 0
        controlsHidden = settings?.padHidden ?? false
        lastError = nil
        consoleStatus = nil
        consoleStatusAt = nil
        consoleTakesInput = nil
        hasRecentPicture = false
        connect(reason: nil)
        startStatsTimer()
    }

    func stop() {
        userStopped = true
        suspended = false
        generation += 1
        reconnectItem?.cancel()
        teardown()
        audio.stop()
        consoleTakesInput = nil
        consoleStatus = nil
        hasRecentPicture = false
        phase = .idle
    }

    func suspend() {
        guard !suspended else { return }
        suspended = true
        guard !userStopped else { return }
        reconnectItem?.cancel()
        generation += 1
        netQueue.async { [pad] in pad.suspended = true }
        teardown()
        audio.stop()
        consoleTakesInput = nil
        consoleStatus = nil
        hasRecentPicture = false
        statsTimer?.invalidate()
        statsTimer = nil
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        guard !userStopped else { return }
        netQueue.async { [pad] in
            pad.suspended = false
        }
        failCount = 0
        lastError = nil
        connect(reason: nil)
        startStatsTimer()
    }

    func padStateChanged(_ state: PadState) {
        netQueue.async { [pad] in
            pad.setState(state)
        }
    }

    func setMuted(_ muted: Bool) {
        audio.setMuted(muted)
    }

    func setAudioPreset(_ rawValue: Int) {
        audio.setPreset(rawValue)
    }

    func setPadHidden(_ hidden: Bool) {
        controlsHidden = hidden
        netQueue.async { [pad] in
            pad.padHidden = hidden
        }
    }

    private final class SendBox: @unchecked Sendable {
        var connection: Connection?
    }

    private func connect(reason: String?) {
        generation += 1
        let gen = generation
        let attempt = failCount + 1
        phase = reason.map { .reconnecting(attempt: attempt, reason: $0) } ?? .connecting(attempt: attempt)
        netQueue.async { [weak self, pad, decoder, audio, sendBox, netQueue, host, port] in
            let conn = Connection(host: host, port: port, queue: netQueue)
            conn.onReady = { [weak self, weak conn] in
                guard let conn, sendBox.connection === conn else { return }
                conn.send(ViewerMessages.keyframe)
                print("Viewer: SFTK")
                pad.connected = true
                Task { @MainActor in self?.connected(gen: gen) }
            }
            conn.onPackets = { [weak self, weak conn] packets in
                guard let conn, sendBox.connection === conn else { return }
                for packet in packets {
                    if packet.isVideo {
                        decoder.submit(packet)
                    } else if packet.isAudio {
                        audio.append(packet.payload)
                    } else if packet.isStatus {
                        let status = StatusPacket(packet: packet)
                        Task { @MainActor in self?.statusReceived(status, gen: gen) }
                    }
                }
                let sawVideo = packets.contains { $0.isVideo }
                Task { @MainActor in self?.packetsSeen(gen: gen, sawVideo: sawVideo) }
            }
            conn.onInputCapability = { [weak self, weak conn] takes in
                guard let conn, sendBox.connection === conn else { return }
                pad.consoleTakesInput = takes
                Task { @MainActor in self?.capabilitySeen(takes, gen: gen) }
            }
            conn.onFail = { [weak self] failure in
                Task { @MainActor in self?.failed(failure, gen: gen) }
            }
            sendBox.connection = conn
            conn.start()
        }
    }

    private func connected(gen: Int) {
        guard gen == generation, !suspended, !userStopped else { return }
        phase = .waitingPicture
        audio.setMuted(settings?.muted ?? false)
        audio.setPreset(settings?.audioPreset ?? AudioJitterBuffer.Preset.standard.rawValue)
        audio.start()
        let hidden = controlsHidden
        netQueue.async { [pad] in
            pad.padHidden = hidden
        }
    }

    private func packetsSeen(gen: Int, sawVideo: Bool) {
        guard gen == generation else { return }
        failCount = 0
        if sawVideo {
            consoleStatus = nil
            consoleStatusAt = nil
        }
    }

    private func statusReceived(_ status: StatusPacket, gen: Int) {
        guard gen == generation else { return }
        consoleStatus = status
        consoleStatusAt = Date()
    }

    private func capabilitySeen(_ takes: Bool, gen: Int) {
        guard gen == generation, consoleTakesInput != takes else { return }
        consoleTakesInput = takes
    }

    private func firstFrameDisplayed() {
        guard !suspended, !userStopped, phase == .waitingPicture || phase == .playing else { return }
        phase = .playing
        hasRecentPicture = true
    }

    private func failed(_ failure: Connection.Failure, gen: Int) {
        guard gen == generation else { return }
        teardown()
        audio.stop()
        consoleTakesInput = nil
        consoleStatus = nil
        hasRecentPicture = false
        guard !userStopped, !suspended else {
            phase = .idle
            return
        }
        failCount += 1
        let reason = failure.reason
        lastError = reason
        let delay: TimeInterval
        switch failCount {
        case 1: delay = 1
        case 2: delay = 2
        case 3: delay = 4
        default: delay = 5
        }
        phase = .reconnecting(attempt: failCount + 1, reason: reason)
        let item = DispatchWorkItem { [weak self] in
            self?.reconnect(gen: gen, reason: reason)
        }
        reconnectItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func reconnect(gen: Int, reason: String) {
        guard gen == generation, !userStopped, !suspended else { return }
        connect(reason: reason)
    }

    private func teardown() {
        netQueue.async { [pad, decoder, audio, sendBox] in
            pad.connected = false
            pad.consoleTakesInput = nil
            sendBox.connection?.close()
            sendBox.connection = nil
            decoder.flush()
            audio.clearBuffer()
        }
    }

    private func startStatsTimer() {
        guard statsTimer == nil else { return }
        lastTick = MonotonicClock.now()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let video = decoder.snapshot()
        let audioStats = audio.snapshot()
        let bytes = netQueue.sync { sendBox.connection?.bytesReceived ?? lastBytes }
        let now = MonotonicClock.now()
        let elapsed = max(now - lastTick, 0.01)
        stats.width = video.width
        stats.height = video.height
        stats.fps = Double(max(0, video.displayed - lastDisplayed)) / elapsed
        stats.mbps = Double(max(0, bytes - lastBytes)) * 8 / elapsed / 1_000_000
        stats.decodeMs = video.decodeMs
        stats.consoleAgeMs = video.consoleAgeMs
        stats.displayMs = video.displayMs
        stats.resets = video.resetCount
        stats.dropped = video.dropped
        stats.audioBufferedMs = audioStats.bufferedMs
        stats.audioUnderruns = audioStats.underruns
        stats.audioDroppedMs = audioStats.droppedMs
        stats.padState = padStateText()
        hasRecentPicture = video.pictureAge < 1.0
        lastBytes = bytes
        lastDisplayed = video.displayed
        lastTick = now
        if phase == .idle && userStopped {
            statsTimer?.invalidate()
            statsTimer = nil
        }
    }

    private func padStateText() -> String {
        if settings?.padHidden == true { return "已隐藏" }
        switch consoleTakesInput {
        case true: return "已接管"
        case false: return "主机未开启"
        case nil: return "未知"
        }
    }
}
