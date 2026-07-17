import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

// MARK: - WAV Writer

final class WAVWriter {
    private let url: URL
    private var fileHandle: FileHandle?
    private var dataByteCount: UInt32 = 0
    private let lock = NSLock()
    let sampleRate: UInt32
    let channelCount: UInt16

    init(url: URL, sampleRate: UInt32 = 16000, channelCount: UInt16 = 1) {
        self.url = url
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    func open() throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: url)
        writeHeader(dataSize: 0)
    }

    private func le16(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return withUnsafeBytes(of: &x) { Data($0) }
    }

    private func le32(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return withUnsafeBytes(of: &x) { Data($0) }
    }

    private func writeHeader(dataSize: UInt32) {
        var h = Data(capacity: 44)
        h += "RIFF".data(using: .ascii)!
        h += le32(dataSize + 36)
        h += "WAVE".data(using: .ascii)!
        h += "fmt ".data(using: .ascii)!
        h += le32(16)
        h += le16(1)  // PCM
        h += le16(channelCount)
        h += le32(sampleRate)
        h += le32(sampleRate * UInt32(channelCount) * 2)  // byte rate
        h += le16(channelCount * 2)  // block align
        h += le16(16)  // bits per sample
        h += "data".data(using: .ascii)!
        h += le32(dataSize)
        fileHandle?.seek(toFileOffset: 0)
        fileHandle?.write(h)
    }

    func writeSamples(_ samples: [Float]) {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            var v = Int16(max(-1.0, min(1.0, s)) * 32767.0).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        lock.lock()
        fileHandle?.seekToEndOfFile()
        fileHandle?.write(pcm)
        dataByteCount += UInt32(pcm.count)
        lock.unlock()
    }

    func finalize() {
        lock.lock()
        defer { lock.unlock() }
        writeHeader(dataSize: dataByteCount)
        fileHandle?.closeFile()
        fileHandle = nil
    }
}

// MARK: - Audio Mixer

/// Mixes several continuous 16kHz mono sources into one WAV by summing
/// time-aligned samples. Each source advances its own cursor; samples are
/// flushed to disk up to the point every still-active source has reached,
/// so the two streams stay in sync without ffmpeg post-processing.
final class AudioMixer {
    private let writer: WAVWriter
    private let lock = NSLock()

    // Mixed samples not yet flushed; accumulator[0] == absolute index `flushedCount`.
    private var accumulator: [Float] = []
    private var flushedCount: Int = 0

    // Per-source absolute write position. Int.max marks a finished source,
    // excluding it from the flush watermark.
    private var cursors: [Int]

    init(writer: WAVWriter, sourceCount: Int) {
        self.writer = writer
        self.cursors = Array(repeating: 0, count: sourceCount)
    }

    func append(source: Int, samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let start = cursors[source]
        let needed = (start + samples.count) - flushedCount
        if needed > accumulator.count {
            accumulator.append(contentsOf: repeatElement(0, count: needed - accumulator.count))
        }

        var idx = start - flushedCount
        for s in samples {
            accumulator[idx] += s
            idx += 1
        }
        cursors[source] = start + samples.count

        flushReady()
    }

    /// Mark a source as done so the flush watermark no longer waits on it.
    func finish(source: Int) {
        lock.lock()
        defer { lock.unlock() }
        cursors[source] = Int.max
        flushReady()
    }

    // Flush every sample all active sources have already passed.
    private func flushReady() {
        let watermark = cursors.min() ?? Int.max
        let flushable = min(watermark - flushedCount, accumulator.count)
        guard flushable > 0 else { return }
        writer.writeSamples(Array(accumulator[0..<flushable]))
        accumulator.removeFirst(flushable)
        flushedCount += flushable
    }
}

// MARK: - System Audio via SCStream

final class SystemAudioCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    let mixer: AudioMixer
    let sourceIndex: Int

    init(mixer: AudioMixer, sourceIndex: Int) {
        self.mixer = mixer
        self.sourceIndex = sourceIndex
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }

        // Determine dynamic size needed for AudioBufferList
        var listSize = 0
        var blockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &listSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard listSize > 0 else { return }

        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: listSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPtr.deallocate() }
        let ablPtr = rawPtr.assumingMemoryBound(to: AudioBufferList.self)

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablPtr,
            bufferListSize: listSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(ablPtr)
        guard let first = buffers.first, let dataPtr = first.mData else { return }

        let frameCount = Int(first.mDataByteSize) / MemoryLayout<Float32>.size
        let floatPtr = dataPtr.assumingMemoryBound(to: Float32.self)

        // Detect channel count from format description to downmix if stereo
        var channels: UInt32 = 1
        if let fmt = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee
        {
            channels = asbd.mChannelsPerFrame
        }

        let samples: [Float]
        if channels == 2 {
            let all = Array(UnsafeBufferPointer(start: floatPtr, count: frameCount))
            var mono: [Float] = []
            mono.reserveCapacity(all.count / 2)
            var idx = 0
            while idx + 1 < all.count {
                mono.append((all[idx] + all[idx + 1]) * 0.5)
                idx += 2
            }
            samples = mono
        } else {
            samples = Array(UnsafeBufferPointer(start: floatPtr, count: frameCount))
        }

        mixer.append(source: sourceIndex, samples: samples)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fputs("[SCRecorder] Stream stopped: \(error.localizedDescription)\n", stderr)
    }
}

// MARK: - Mic Capturer via AVAudioEngine

final class MicCapturer {
    // Assigned once the mixer's source count is known (after prepare succeeds).
    var mixer: AudioMixer?
    let sourceIndex: Int
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var inputFmt: AVAudioFormat?
    private var outputFmt: AVAudioFormat?

    init(sourceIndex: Int) {
        self.sourceIndex = sourceIndex
    }

    /// Validate the input device and build the 16kHz converter. Throws if the
    /// mic is unavailable, before any mixer source has been committed to.
    func prepare() throws {
        let inFmt = engine.inputNode.outputFormat(forBus: 0)
        guard inFmt.sampleRate > 0 else {
            throw NSError(domain: "SCRecorder", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }
        guard let outFmt = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1) else {
            throw NSError(domain: "SCRecorder", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot create 16kHz output format"])
        }
        guard let conv = AVAudioConverter(from: inFmt, to: outFmt) else {
            throw NSError(domain: "SCRecorder", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot create audio converter"])
        }
        self.inputFmt = inFmt
        self.outputFmt = outFmt
        self.converter = conv
    }

    func start() throws {
        guard let inputFmt = self.inputFmt else {
            throw NSError(domain: "SCRecorder", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "MicCapturer.start() called before prepare()"])
        }

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFmt) { [weak self] buffer, _ in
            guard let self, let conv = self.converter, let outFmt = self.outputFmt else { return }

            let ratio = 16000.0 / inputFmt.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

            guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: capacity) else { return }

            var err: NSError?
            conv.convert(to: outBuf, error: &err) { _, status in
                status.pointee = .haveData
                return buffer
            }

            guard err == nil,
                outBuf.frameLength > 0,
                let channelData = outBuf.floatChannelData?[0]
            else { return }

            let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(outBuf.frameLength)))
            self.mixer?.append(source: self.sourceIndex, samples: samples)
        }

        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        mixer?.finish(source: sourceIndex)
    }
}

// MARK: - Main

func run() async {
    let args = CommandLine.arguments

    guard let outIdx = args.firstIndex(of: "--output"), outIdx + 1 < args.count else {
        fputs("Usage: SCRecorder --output <path.wav> [--mic]\n", stderr)
        exit(1)
    }

    let outputPath = args[outIdx + 1]
    let captureMic = args.contains("--mic")

    // Single output writer — system audio and mic are mixed into this one file.
    let writer = WAVWriter(url: URL(fileURLWithPath: outputPath), sampleRate: 16000, channelCount: 1)
    do {
        try writer.open()
    } catch {
        fputs("[SCRecorder] Cannot open output file: \(error)\n", stderr)
        exit(1)
    }

    // Prepare the mic before sizing the mixer: if it fails to prepare, we
    // record system audio only as a single source.
    var micCapturer: MicCapturer?
    if captureMic {
        let mc = MicCapturer(sourceIndex: 1)
        do {
            try mc.prepare()
            micCapturer = mc
        } catch {
            fputs("[SCRecorder] Warning: mic unavailable, recording system audio only: \(error)\n", stderr)
        }
    }

    // System audio is source 0; mic (if prepared) is source 1.
    let sourceCount = micCapturer != nil ? 2 : 1
    let mixer = AudioMixer(writer: writer, sourceCount: sourceCount)

    if let mc = micCapturer {
        mc.mixer = mixer
        do {
            try mc.start()
            fputs("[SCRecorder] Mic capture → mixed into \(outputPath)\n", stderr)
        } catch {
            // Mic dropped out after the watermark was sized for it — release it.
            mixer.finish(source: 1)
            micCapturer = nil
            fputs("[SCRecorder] Warning: mic start failed, system audio only: \(error)\n", stderr)
        }
    }

    // Get shareable content (triggers screen recording permission prompt on first run)
    let content: SCShareableContent
    do {
        content = try await SCShareableContent.current
    } catch {
        fputs("[SCRecorder] SCShareableContent.current failed: \(error)\n", stderr)
        fputs("[SCRecorder] Grant Screen Recording permission in System Settings → Privacy & Security.\n", stderr)
        exit(1)
    }

    guard let display = content.displays.first else {
        fputs("[SCRecorder] No display found.\n", stderr)
        exit(1)
    }

    // Audio-only stream (Sonoma 14.2+: no video needed)
    let config = SCStreamConfiguration()
    config.capturesAudio = true
    config.sampleRate = 16000
    config.channelCount = 1
    config.excludesCurrentProcessAudio = false

    let filter = SCContentFilter(
        display: display,
        excludingApplications: [],
        exceptingWindows: []
    )

    let capturer = SystemAudioCapturer(mixer: mixer, sourceIndex: 0)
    let stream = SCStream(filter: filter, configuration: config, delegate: capturer)

    do {
        try stream.addStreamOutput(capturer, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()
    } catch {
        fputs("[SCRecorder] Failed to start capture: \(error)\n", stderr)
        exit(1)
    }

    fputs("[SCRecorder] Recording started.\n", stderr)

    // Use DispatchSource for reliable signal handling in async context
    let stopSema = DispatchSemaphore(value: 0)
    let sigtermSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    sigtermSrc.setEventHandler { stopSema.signal() }
    sigtermSrc.resume()
    signal(SIGTERM, SIG_IGN)

    let sigintSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigintSrc.setEventHandler { stopSema.signal() }
    sigintSrc.resume()
    signal(SIGINT, SIG_IGN)

    // Block until signal
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async {
            stopSema.wait()
            continuation.resume()
        }
    }

    fputs("[SCRecorder] Stopping...\n", stderr)

    do {
        try await stream.stopCapture()
    } catch {
        fputs("[SCRecorder] Warning: stopCapture error: \(error)\n", stderr)
    }
    mixer.finish(source: 0)
    micCapturer?.stop()  // finishes source 1 and flushes the mixer tail

    // All sources finished — flush any remaining tail and close the file.
    writer.finalize()

    fputs("[SCRecorder] Saved → \(outputPath)\n", stderr)
    exit(0)
}

Task { await run() }
dispatchMain()
