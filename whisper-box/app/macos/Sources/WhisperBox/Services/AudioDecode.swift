import AVFoundation
import Foundation

/// Decodes any AV-readable file (wav, mp3, m4a, mp4, mov, caf …) to the raw format WhisperKit
/// expects: **16 kHz mono 32-bit float PCM**. We use `AVAssetReader` rather than WhisperKit's
/// `AVAudioFile`-based loader, which throws Core Audio -50 on mp4/mov containers (compressed AAC
/// and files carrying a video track, e.g. ScreenCaptureKit output). `AVAssetReader` handles every
/// container/codec uniformly and performs the decode, sample-rate conversion, and channel downmix.
enum AudioDecode {
    static func pcm16kMono(path: String) async throws -> [Float] {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "Transcription", code: 100, userInfo:
                [NSLocalizedDescriptionKey: "No audio track found in \(url.lastPathComponent)"])
        }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw NSError(domain: "Transcription", code: 101, userInfo:
                [NSLocalizedDescriptionKey: "Cannot decode audio from \(url.lastPathComponent)"])
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "Transcription", code: 102, userInfo:
                [NSLocalizedDescriptionKey: "Failed to start decoding \(url.lastPathComponent)"])
        }

        var samples: [Float] = []
        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            if let block = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(block)
                let count = length / MemoryLayout<Float>.size
                if count > 0 {
                    var chunk = [Float](repeating: 0, count: count)
                    chunk.withUnsafeMutableBytes { raw in
                        _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                                       destination: raw.baseAddress!)
                    }
                    samples.append(contentsOf: chunk)
                }
            }
            CMSampleBufferInvalidate(sampleBuffer)
        }

        guard reader.status != .failed else {
            throw reader.error ?? NSError(domain: "Transcription", code: 103, userInfo:
                [NSLocalizedDescriptionKey: "Failed to decode audio from \(url.lastPathComponent)"])
        }
        return samples
    }
}
