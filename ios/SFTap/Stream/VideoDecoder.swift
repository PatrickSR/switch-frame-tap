// SPDX-License-Identifier: GPL-2.0-only
import AVFoundation
import CoreMedia
import Foundation
import SFTCore
import VideoToolbox

final class VideoDecoder: @unchecked Sendable {
    struct Snapshot {
        var decoded = 0
        var displayed = 0
        var dropped = 0
        var resetCount = 0
        var decodeMs = 0.0
        var displayMs = 0.0
        var width = 0
        var height = 0
        var consoleAgeMs = 0.0
        var pictureAge = Double.greatestFiniteMagnitude
    }

    var onKeyframeRequest: (@Sendable () -> Void)?
    var onFirstFrame: (@Sendable () -> Void)?

    private struct Item {
        let packet: Packet
        let needsReset: Bool
        let generation: Int
    }

    private final class Output: @unchecked Sendable {
        var status = noErr as OSStatus
        var image: CVImageBuffer?
    }

    private let lock = NSLock()
    private var policy = VideoFramePolicy()
    private var pending: [Item] = []
    private var drainScheduled = false
    private var generation = 0
    private var flushRequested = false
    private let queue = DispatchQueue(label: "sft.decode")
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private var decoded = 0
    private var displayed = 0
    private var droppedByReset = 0
    private var displaySkipped = 0
    private var decodeTimes: [Double] = []
    private var latencies: [Double] = []
    private var lastDisplayedAt: TimeInterval?
    private var lastWidth = 0
    private var lastHeight = 0
    private var lastAgeMs = 0.0
    private var awaitingFirst = true

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
    }

    func submit(_ packet: Packet) {
        lock.lock()
        let now = MonotonicClock.now()
        let oldest = pending.first.map { now - $0.packet.receivedAt } ?? 0
        let decision = policy.consume(
            packet.header,
            now: now,
            queuedFrames: pending.count,
            oldestAge: oldest
        )
        if decision.requestKeyframe { onKeyframeRequest?() }
        guard decision.decode else {
            lock.unlock()
            return
        }
        if decision.resetDecoder {
            droppedByReset += pending.count
            pending.removeAll()
        }
        pending.append(Item(packet: packet, needsReset: decision.resetDecoder, generation: generation))
        if !drainScheduled {
            drainScheduled = true
            queue.async { [weak self] in self?.drain() }
        }
        lock.unlock()
    }

    func flush() {
        lock.lock()
        generation += 1
        pending.removeAll()
        policy.reset()
        awaitingFirst = true
        lastDisplayedAt = nil
        flushRequested = true
        if !drainScheduled {
            drainScheduled = true
            queue.async { [weak self] in self?.drain() }
        }
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        var snap = Snapshot()
        snap.decoded = decoded
        snap.displayed = displayed
        snap.dropped = policy.droppedCount + droppedByReset + displaySkipped
        snap.resetCount = policy.resetCount
        snap.decodeMs = decodeTimes.isEmpty ? 0 : decodeTimes.reduce(0, +) / Double(decodeTimes.count)
        snap.displayMs = percentile50(latencies)
        snap.width = lastWidth
        snap.height = lastHeight
        snap.consoleAgeMs = lastAgeMs
        if let at = lastDisplayedAt {
            snap.pictureAge = MonotonicClock.now() - at
        }
        return snap
    }

    private func drain() {
        while true {
            lock.lock()
            if flushRequested {
                flushRequested = false
                lock.unlock()
                invalidate()
                displayLayer?.sampleBufferRenderer.flush()
                displayLayer?.flushAndRemoveImage()
                continue
            }
            guard let item = pending.first else {
                drainScheduled = false
                lock.unlock()
                return
            }
            pending.removeFirst()
            let isLast = pending.isEmpty
            lock.unlock()
            _ = process(item, isLast: isLast)
        }
    }

    private func process(_ item: Item, isLast: Bool) -> Bool {
        let packet = item.packet
        lock.lock()
        let current = item.generation == generation
        lock.unlock()
        guard current else { return false }
        if item.needsReset || packet.isKeyFrame || session == nil {
            guard let sets = try? H264.parameterSets(in: packet.payload) else {
                print("decode: no parameter sets in access unit")
                decoderFailed(generation: item.generation)
                return false
            }
            if item.needsReset || sets.sps != sps || sets.pps != pps || session == nil {
                guard makeSession(sps: sets.sps, pps: sets.pps) else {
                    print("decode: VTDecompressionSessionCreate failed")
                    decoderFailed(generation: item.generation)
                    return false
                }
                sps = sets.sps
                pps = sets.pps
            }
        }
        guard session != nil, format != nil, let avcc = try? H264.accessUnit(from: packet.payload), !avcc.isEmpty else {
            print("decode: access unit conversion failed")
            decoderFailed(generation: item.generation)
            return false
        }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avcc.count,
            blockAllocator: kCFAllocatorMalloc,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: 0,
            blockBufferOut: &block
        ) == kCMBlockBufferNoErr, let block else {
            decoderFailed(generation: item.generation)
            return false
        }
        let copyStatus = avcc.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: $0.count)
        }
        guard copyStatus == noErr else {
            decoderFailed(generation: item.generation)
            return false
        }
        var input: CMSampleBuffer?
        var sampleSize = avcc.count
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &input
        ) == noErr, let input, let session else {
            decoderFailed(generation: item.generation)
            return false
        }
        let started = MonotonicClock.now()
        let output = Output()
        let callStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: input,
            flags: [],
            infoFlagsOut: nil
        ) { status, _, imageBuffer, _, _, _ in
            output.status = status
            output.image = imageBuffer
        }
        let decodeMs = (MonotonicClock.now() - started) * 1000
        guard callStatus == noErr, output.status == noErr, let image = output.image else {
            print("decode: frame failed call=\(callStatus) out=\(output.status)")
            decoderFailed(generation: item.generation)
            return false
        }
        lock.lock()
        guard item.generation == generation else {
            lock.unlock()
            return false
        }
        decoded += 1
        record(&decodeTimes, decodeMs)
        lastWidth = Int(packet.header.width)
        lastHeight = Int(packet.header.height)
        lastAgeMs = Double(packet.header.consoleAgeMicros) / 1000
        lock.unlock()
        if isLast { display(image, packet: packet, generation: item.generation) }
        return true
    }

    private func display(_ image: CVImageBuffer, packet: Packet, generation: Int) {
        guard let renderer = displayLayer?.sampleBufferRenderer else { return }
        var imageFormat: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: image,
            formatDescriptionOut: &imageFormat
        ) == noErr, let imageFormat else { return }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var output: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: image,
            formatDescription: imageFormat,
            sampleTiming: &timing,
            sampleBufferOut: &output
        ) == noErr, let output else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(output, createIfNecessary: true) {
            let sample = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                sample,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            renderer.flush()
            decoderFailed(generation: generation)
            return
        }
        guard renderer.isReadyForMoreMediaData else {
            lock.lock()
            displaySkipped += 1
            lock.unlock()
            return
        }
        lock.lock()
        guard generation == self.generation else {
            lock.unlock()
            return
        }
        renderer.enqueue(output)
        displayed += 1
        let now = MonotonicClock.now()
        record(&latencies, (now - packet.receivedAt) * 1000)
        lastDisplayedAt = now
        let first = awaitingFirst
        awaitingFirst = false
        lock.unlock()
        if first { onFirstFrame?() }
    }

    private func decoderFailed(generation: Int) {
        invalidate()
        lock.lock()
        guard generation == self.generation else {
            lock.unlock()
            return
        }
        droppedByReset += pending.count
        pending.removeAll()
        let request = policy.decoderFailed(now: MonotonicClock.now())
        awaitingFirst = true
        lock.unlock()
        if request { onKeyframeRequest?() }
        displayLayer?.sampleBufferRenderer.flush()
    }

    private func makeSession(sps: Data, pps: Data) -> Bool {
        invalidate()
        var description: CMVideoFormatDescription?
        var status = sps.withUnsafeBytes { spsRaw in
            pps.withUnsafeBytes { ppsRaw in
                var pointers = [
                    spsRaw.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    ppsRaw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                ]
                var sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &pointers,
                    parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &description
                )
            }
        }
        guard status == noErr, let videoFormat = description else { return false }
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        var created: VTDecompressionSession?
        status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: videoFormat,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &created
        )
        guard status == noErr, let created else { return false }
        VTSessionSetProperty(created, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        session = created
        format = videoFormat
        return true
    }

    private func invalidate() {
        if let session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
        format = nil
    }

    private func record(_ list: inout [Double], _ value: Double) {
        list.append(value)
        if list.count > 120 { list.removeFirst(list.count - 120) }
    }

    private func percentile50(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
