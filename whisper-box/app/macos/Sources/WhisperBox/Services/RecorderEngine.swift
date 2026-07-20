import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

// Audio capture primitives, ported in-process from app/swift/SCRecorder.swift.
// System audio (SCStream) + optional mic (AVAudioEngine) are mixed into one
// 16 kHz mono WAV. The CLI/signal `run()` is replaced by RecordingService.

// MARK: - WAV Writer

final class WAVWriter {
    private let url: URL
    private var fileHandle: FileHandle?
    private var dataByteCount: UInt32 = 0
    private let lock = NSLock()
    let sampleRate: UInt32
    let channelCount: UInt16

    init(url: URL, sampleRate: UInt32 = 16000, channelCount: UInt16 = 1) {
        self.url = url; self.sampleRate = sampleRate; self.channelCount = channelCount
    }

    func open() throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: url)
        writeHeader(dataSize: 0)
    }

    private func le16(_ v: UInt16) -> Data { var x = v.littleEndian; return withUnsafeBytes(of: &x) { Data($0) } }
    private func le32(_ v: UInt32) -> Data { var x = v.littleEndian; return withUnsafeBytes(of: &x) { Data($0) } }

    private func writeHeader(dataSize: UInt32) {
        var h = Data(capacity: 44)
        h += "RIFF".data(using: .ascii)!; h += le32(dataSize + 36); h += "WAVE".data(using: .ascii)!
        h += "fmt ".data(using: .ascii)!; h += le32(16); h += le16(1); h += le16(channelCount)
        h += le32(sampleRate); h += le32(sampleRate * UInt32(channelCount) * 2)
        h += le16(channelCount * 2); h += le16(16)
        h += "data".data(using: .ascii)!; h += le32(dataSize)
        fileHandle?.seek(toFileOffset: 0); fileHandle?.write(h)
    }

    func writeSamples(_ samples: [Float]) {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            var v = Int16(max(-1.0, min(1.0, s)) * 32767.0).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        lock.lock(); fileHandle?.seekToEndOfFile(); fileHandle?.write(pcm)
        dataByteCount += UInt32(pcm.count); lock.unlock()
    }

    /// #22 — rewrite the RIFF header from the bytes written so far *without closing*,
    /// so a hard crash / power loss still leaves a playable file (finalize writes the
    /// authoritative header on a clean stop). Cheap: the handle is already open.
    func flushHeader() {
        lock.lock(); defer { lock.unlock() }
        guard fileHandle != nil else { return }
        writeHeader(dataSize: dataByteCount)                 // seeks to 0, writes 44 bytes
        fileHandle?.seekToEndOfFile()                        // leave the cursor at the tail
    }

    func finalize() {
        lock.lock(); defer { lock.unlock() }
        writeHeader(dataSize: dataByteCount); fileHandle?.closeFile(); fileHandle = nil
    }
}

// MARK: - Audio Mixer (with §10.1 pause gate)

final class AudioMixer {
    private let writer: WAVWriter
    private let lock = NSLock()
    private var accumulator: [Float] = []
    private var flushedCount: Int = 0
    private var cursors: [Int]
    private var lastAdvance: [Date]          // #24 — per-source last-delivery time
    private var stalled: Set<Int> = []
    private let stallThreshold: TimeInterval = 8

    /// §10.1 — while paused, incoming samples are dropped so paused time is
    /// excluded and the saved audio stays contiguous (the SCStream stays alive).
    var isPaused = false

    /// Phase 5 — receives each flushed (system+mic mixed) slice for live
    /// transcription. Must be lightweight (it runs under the mixer lock).
    var onFlush: (([Float]) -> Void)?

    /// #24 — invoked (source index) when a source is declared stalled and dropped.
    var onStall: ((Int) -> Void)?

    /// Clock seam — injectable so the stall detector is unit-testable (default: wall clock).
    private let now: () -> Date

    init(writer: WAVWriter, sourceCount: Int, now: @escaping () -> Date = { Date() }) {
        self.writer = writer
        self.now = now
        self.cursors = Array(repeating: 0, count: sourceCount)
        self.lastAdvance = Array(repeating: now(), count: sourceCount)
    }

    func append(source: Int, samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        guard !isPaused else { return }
        // #1 — a finished/stalled source is parked at Int.max; late buffers from a
        // source whose capture wasn't actually stopped (checkStall marks it done but
        // leaves the SCStream/mic running) would overflow `start + samples.count`.
        guard cursors[source] != Int.max else { return }

        let start = cursors[source]
        let needed = (start + samples.count) - flushedCount
        if needed > accumulator.count {
            accumulator.append(contentsOf: repeatElement(0, count: needed - accumulator.count))
        }
        var idx = start - flushedCount
        for s in samples { accumulator[idx] += s; idx += 1 }
        cursors[source] = start + samples.count
        lastAdvance[source] = now()
        flushReady()
    }

    func finish(source: Int) {
        lock.lock(); defer { lock.unlock() }
        _finish(source: source)
    }

    private func _finish(source: Int) {
        cursors[source] = Int.max
        flushReady()
    }

    /// #24 fix — call on **resume** so a long pause isn't mistaken for a stall. During
    /// pause `append` early-returns without touching `lastAdvance`, so it still holds
    /// the pre-pause time; without this, a pause longer than `stallThreshold` makes
    /// `checkStall` drop a still-live source the moment the other one delivers again.
    func resetStallClocks() {
        lock.lock(); defer { lock.unlock() }
        let t = now()
        for i in lastAdvance.indices { lastAdvance[i] = t }
    }

    /// #24 — if one source goes silent (mic unplugged, SCStream stalls without
    /// `didStopWithError`) while another keeps delivering, the `min(cursors)`
    /// watermark freezes and audio accumulates unbounded with the file + live
    /// transcript stuck. Detect a source idle past the threshold *while another is
    /// still moving* and finish it so flushing resumes. Called ~1 Hz from the timer.
    func checkStall() {
        var stalledNow: [Int] = []
        lock.lock()
        if cursors.count > 1 && !isPaused {
            let t = now()
            for s in 0..<cursors.count where cursors[s] != Int.max && !stalled.contains(s) {
                guard t.timeIntervalSince(lastAdvance[s]) > stallThreshold else { continue }
                let othersMoving = (0..<cursors.count).contains { o in
                    o != s && cursors[o] != Int.max && t.timeIntervalSince(lastAdvance[o]) < stallThreshold
                }
                if othersMoving {
                    stalled.insert(s)
                    stalledNow.append(s)
                    _finish(source: s)
                }
            }
        }
        lock.unlock()
        stalledNow.forEach { onStall?($0) }   // notify outside the lock
    }

    private func flushReady() {
        let watermark = cursors.min() ?? Int.max
        let flushable = min(watermark - flushedCount, accumulator.count)
        guard flushable > 0 else { return }
        let slice = Array(accumulator[0..<flushable])
        writer.writeSamples(slice)
        onFlush?(slice)                 // tee to live transcriber (lightweight)
        accumulator.removeFirst(flushable)
        flushedCount += flushable
    }
}

// MARK: - System Audio via SCStream

final class SystemAudioCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    let mixer: AudioMixer
    let sourceIndex: Int
    var onStop: ((Error) -> Void)?

    init(mixer: AudioMixer, sourceIndex: Int) {
        self.mixer = mixer; self.sourceIndex = sourceIndex
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        var listSize = 0
        var blockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &listSize, bufferListOut: nil,
            bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: 0, blockBufferOut: nil)
        guard listSize > 0 else { return }

        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: listSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPtr.deallocate() }
        let ablPtr = rawPtr.assumingMemoryBound(to: AudioBufferList.self)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: ablPtr,
            bufferListSize: listSize, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: 0, blockBufferOut: &blockBuffer)
        guard status == noErr else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(ablPtr)
        guard let first = buffers.first, let dataPtr = first.mData else { return }
        let frameCount = Int(first.mDataByteSize) / MemoryLayout<Float32>.size
        let floatPtr = dataPtr.assumingMemoryBound(to: Float32.self)

        var channels: UInt32 = 1
        if let fmt = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee {
            channels = asbd.mChannelsPerFrame
        }

        let samples: [Float]
        if channels == 2 {
            let all = Array(UnsafeBufferPointer(start: floatPtr, count: frameCount))
            var mono: [Float] = []; mono.reserveCapacity(all.count / 2)
            var idx = 0
            while idx + 1 < all.count { mono.append((all[idx] + all[idx + 1]) * 0.5); idx += 2 }
            samples = mono
        } else {
            samples = Array(UnsafeBufferPointer(start: floatPtr, count: frameCount))
        }
        mixer.append(source: sourceIndex, samples: samples)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onStop?(error) }
}

// MARK: - Video via SCStream → AVAssetWriter (#35)

/// Encodes `.screen` sample buffers from an SCStream into an H.264 `.mp4`.
/// Audio is handled separately (the WAV pipeline stays the transcription source);
/// this is a standalone video deliverable. Only `.complete` frames are appended,
/// and the writer session starts on the first frame so timestamps line up.
final class VideoRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    let url: URL
    var onStop: ((Error) -> Void)?

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false
    private var failed = false
    private var paused = false
    private let lock = NSLock()

    /// #4 — while paused, drop incoming frames so the .mp4 doesn't record private
    /// screen content the user believes is paused (mirrors the AudioMixer pause gate).
    func setPaused(_ p: Bool) { lock.lock(); paused = p; lock.unlock() }

    init(url: URL, width: Int, height: Int) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        super.init()
        if writer.canAdd(input) { writer.add(input) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        // Skip idle/blank frames (no on-screen change) — only encode complete ones.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete else { return }

        lock.lock(); defer { lock.unlock() }
        guard !paused, !failed else { return }        // #4 — don't record paused frames
        if !started {
            // Only try startWriting once — calling it again on a .failed writer throws.
            guard writer.startWriting() else { failed = true; return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(sampleBuffer) }
    }

    /// Finalize the file. No-op if no frames were ever written. Called only after
    /// the stream's `stopCapture()` has been awaited, so no frame is in flight and
    /// `started` can be read without the sample-handler lock.
    func finish() async {
        guard started else { writer.cancelWriting(); return }
        input.markAsFinished()
        await writer.finishWriting()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onStop?(error) }
}

// MARK: - Mic via AVAudioEngine

final class MicCapturer {
    var mixer: AudioMixer?
    let sourceIndex: Int
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var inputFmt: AVAudioFormat?
    private var outputFmt: AVAudioFormat?

    init(sourceIndex: Int) { self.sourceIndex = sourceIndex }

    func prepare() throws {
        let inFmt = engine.inputNode.outputFormat(forBus: 0)
        guard inFmt.sampleRate > 0 else {
            throw NSError(domain: "Recorder", code: 3, userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }
        guard let outFmt = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1) else {
            throw NSError(domain: "Recorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create 16kHz output format"])
        }
        guard let conv = AVAudioConverter(from: inFmt, to: outFmt) else {
            throw NSError(domain: "Recorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create audio converter"])
        }
        inputFmt = inFmt; outputFmt = outFmt; converter = conv
    }

    func start() throws {
        guard let inputFmt else {
            throw NSError(domain: "Recorder", code: 4, userInfo: [NSLocalizedDescriptionKey: "start() before prepare()"])
        }
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFmt) { [weak self] buffer, _ in
            guard let self, let conv = self.converter, let outFmt = self.outputFmt else { return }
            let ratio = 16000.0 / inputFmt.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: capacity) else { return }
            var err: NSError?
            conv.convert(to: outBuf, error: &err) { _, status in status.pointee = .haveData; return buffer }
            guard err == nil, outBuf.frameLength > 0, let ch = outBuf.floatChannelData?[0] else { return }
            self.mixer?.append(source: self.sourceIndex, samples: Array(UnsafeBufferPointer(start: ch, count: Int(outBuf.frameLength))))
        }
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        mixer?.finish(source: sourceIndex)
    }
}
