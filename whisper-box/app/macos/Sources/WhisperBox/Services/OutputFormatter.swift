import Foundation

/// Renders transcript segments to the supported output formats (txt/srt/vtt).
/// Ports the timestamp/format logic from the Python `whisper_runner`.
enum OutputFormat: String, CaseIterable {
    case txt, srt, vtt
}

enum OutputFormatter {
    static func render(_ segments: [TranscriptSegment], as format: OutputFormat) -> String {
        switch format {
        case .txt: return txt(segments)
        case .srt: return srt(segments)
        case .vtt: return vtt(segments)
        }
    }

    // Plain text — segments joined, trimmed.
    private static func txt(_ segs: [TranscriptSegment]) -> String {
        segs.map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // SubRip: index, "HH:MM:SS,mmm --> HH:MM:SS,mmm", text, blank line.
    private static func srt(_ segs: [TranscriptSegment]) -> String {
        segs.enumerated().map { i, s in
            "\(i + 1)\n\(stamp(s.start, sep: ","))" +
            " --> \(stamp(s.end, sep: ","))\n\(s.text.trimmingCharacters(in: .whitespaces))\n"
        }.joined(separator: "\n")
    }

    // WebVTT: header + "HH:MM:SS.mmm --> HH:MM:SS.mmm" cues.
    private static func vtt(_ segs: [TranscriptSegment]) -> String {
        "WEBVTT\n\n" + segs.map { s in
            "\(stamp(s.start, sep: "."))" +
            " --> \(stamp(s.end, sep: "."))\n\(s.text.trimmingCharacters(in: .whitespaces))\n"
        }.joined(separator: "\n")
    }

    /// seconds → "HH:MM:SS<sep>mmm" (sep is "," for SRT, "." for VTT).
    private static func stamp(_ seconds: Double, sep: String) -> String {
        let total = max(0, seconds)
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = Int(total) % 60
        let ms = Int((total - Double(Int(total))) * 1000)
        return String(format: "%02d:%02d:%02d\(sep)%03d", h, m, s, ms)
    }

    static func fileExtension(for format: OutputFormat) -> String { format.rawValue }
}
