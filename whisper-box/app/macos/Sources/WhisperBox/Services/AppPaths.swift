import Foundation

/// Resolves where transcripts, summaries, and recordings are written.
///
/// The base directory is user-configurable (Settings → `AppSettings.defaultOutputDir`);
/// when unset it **defaults to `~/Whisper Memory`** (the original hardcoded location).
/// Seeded from the persisted setting at launch (`RootView.onAppear`) and updated live
/// when the user picks a new folder in Settings.
@MainActor
enum AppPaths {
    /// Default base when no folder is configured — the original location.
    static let defaultBase = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Whisper Memory")

    private static var base: URL = defaultBase

    /// Point the base at a user-chosen path; "" restores the default.
    static func setBase(_ path: String) {
        base = path.isEmpty
            ? defaultBase
            : URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var transcriptsDir: URL { ensure(base.appendingPathComponent("transcripts")) }
    static var recordingsDir: URL { ensure(base.appendingPathComponent("recordings")) }

    /// True if `path` lives under the configured recordings dir (replaces the old
    /// hardcoded "/Whisper Memory/recordings/" check, which broke once configurable).
    static func isRecording(path: String) -> Bool {
        URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent == "recordings"
    }

    private static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
