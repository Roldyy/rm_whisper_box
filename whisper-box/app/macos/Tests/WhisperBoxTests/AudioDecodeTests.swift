import AVFoundation
import XCTest
@testable import WhisperBox

/// Covers the drop-a-file transcribe decode path (`AudioDecode.pcm16kMono`) — the AVAssetReader
/// route that exists because WhisperKit's own loader fails on mp4/mov. Fixtures are generated at
/// runtime so no binary assets are committed.
final class AudioDecodeTests: XCTestCase {
    private var tmp: [URL] = []
    private func tmpURL(_ ext: String) -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("wbdec_\(UUID().uuidString).\(ext)")
        tmp.append(u); return u
    }
    override func tearDown() {
        tmp.forEach { try? FileManager.default.removeItem(at: $0) }
        tmp = []; super.tearDown()
    }

    /// Write a 16-bit PCM WAV with an interleaved ramp so it isn't pure silence.
    private func writeWAV(_ url: URL, sampleRate: UInt32, channels: UInt16, frames: Int) throws {
        var d = Data()
        func le16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func le32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        let dataSize = UInt32(frames * Int(channels) * 2)
        d.append("RIFF".data(using: .ascii)!); le32(dataSize + 36); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); le32(16); le16(1); le16(channels); le32(sampleRate)
        le32(sampleRate * UInt32(channels) * 2); le16(channels * 2); le16(16)
        d.append("data".data(using: .ascii)!); le32(dataSize)
        for i in 0..<frames {
            let v = Int16(truncatingIfNeeded: ((i % 200) - 100) * 300)
            for _ in 0..<Int(channels) { le16(UInt16(bitPattern: v)) }
        }
        try d.write(to: url)
    }

    func testDecodesMono16kWav() async throws {
        let url = tmpURL("wav")
        try writeWAV(url, sampleRate: 16_000, channels: 1, frames: 16_000)   // 1 s
        let s = try await AudioDecode.pcm16kMono(path: url.path)
        XCTAssertGreaterThan(s.count, 15_000)
        XCTAssertLessThan(s.count, 17_000)
    }

    func testDownmixesAndResamplesStereo44kWav() async throws {
        let url = tmpURL("wav")
        try writeWAV(url, sampleRate: 44_100, channels: 2, frames: 44_100)   // 1 s stereo @44.1k
        let s = try await AudioDecode.pcm16kMono(path: url.path)
        // Resampled to ~16 kHz and downmixed to mono → ~16k samples, NOT ~32k/88k.
        XCTAssertGreaterThan(s.count, 15_000)
        XCTAssertLessThan(s.count, 17_000)
    }

    func testDecodesAacM4a() async throws {
        // A compressed AAC/.m4a container — the class of file WhisperKit's loader chokes on.
        let url = tmpURL("m4a")
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        // Scope the writer so the AVAudioFile deallocates → the container is finalized
        // before we read it back.
        do {
            let file = try AVAudioFile(forWriting: url,
                                       settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                  AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1])
            let frames = AVAudioFrameCount(44_100)                           // 1 s
            let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
            buf.frameLength = frames
            for i in 0..<Int(frames) { buf.floatChannelData![0][i] = sin(Float(i) * 0.05) * 0.5 }
            try file.write(from: buf)
        }

        let s = try await AudioDecode.pcm16kMono(path: url.path)
        // Bound both sides: ~16k after resample+downmix, with slack for AAC priming/trim.
        // A skipped resample (~44.1k) or missing downmix (~2×) must fail this.
        XCTAssertGreaterThan(s.count, 12_000)
        XCTAssertLessThan(s.count, 20_000)
    }

    func testThrowsOnUndecodableFile() async throws {
        let url = tmpURL("wav")
        try Data("not actually audio".utf8).write(to: url)
        do {
            _ = try await AudioDecode.pcm16kMono(path: url.path)
            XCTFail("expected a decode error for a non-audio file")
        } catch { /* expected: fails during AVAsset parse */ }
    }

    /// A valid container that parses fine but has NO audio track — exercises the explicit
    /// "no audio track" guard (AudioDecode line 13), which the garbage-bytes case above skips.
    func testThrowsWithNoAudioTrackErrorForVideoOnlyFile() async throws {
        let url = tmpURL("mp4")
        try await writeVideoOnlyMP4(url)
        do {
            _ = try await AudioDecode.pcm16kMono(path: url.path)
            XCTFail("expected the no-audio-track error")
        } catch {
            let ns = error as NSError
            XCTAssertEqual(ns.domain, "Transcription")
            XCTAssertEqual(ns.code, 100)   // the "No audio track found" guard
        }
    }

    /// A tiny video-only H.264 .mp4 (no audio track). Uses `requestMediaDataWhenReady` so a
    /// frame is only appended while the input is ready (appending when not ready throws).
    private func writeVideoOnlyMP4(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &pb)

        let queue = DispatchQueue(label: "wbtest.video")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var frame: Int64 = 0
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if frame >= 5 {
                        input.markAsFinished()
                        writer.finishWriting { cont.resume() }
                        return
                    }
                    adaptor.append(pb!, withPresentationTime: CMTime(value: frame, timescale: 10))
                    frame += 1
                }
            }
        }
    }
}
