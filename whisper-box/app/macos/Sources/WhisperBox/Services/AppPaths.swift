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

    /// Local staging dir for in-progress recordings. **Always local** (under
    /// Application Support, never the configurable base), so a cloud-sync client
    /// (OneDrive, iCloud Drive…) never sees the growing, still-open WAV. Only the
    /// finalized file is moved into `recordingsDir` (which *may* be a sync folder).
    static var stagingDir: URL {
        let appSup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ensure(appSup.appendingPathComponent("WhisperBox").appendingPathComponent("Staging"))
    }

    /// A collision-free destination in `recordingsDir` for `filename`
    /// (suffixes `-1`, `-2`, … if the name is already taken).
    static func recordingDestination(for filename: String) -> URL {
        uniqueDestination(in: recordingsDir, filename: filename)
    }

    /// A collision-free destination for `filename` inside `dir` (created if needed).
    static func uniqueDestination(in dir: URL, filename: String) -> URL {
        let d = ensure(dir)
        let ext = (filename as NSString).pathExtension
        let stem = (filename as NSString).deletingPathExtension
        var dest = d.appendingPathComponent(filename)
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let name = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            dest = d.appendingPathComponent(name)
            n += 1
        }
        return dest
    }

    /// Cloud sync roots under `~/Library/CloudStorage` (OneDrive, iCloud, Dropbox…),
    /// offered as one-tap output-folder shortcuts in Settings. Empty if none exist.
    static func cloudStorageProviders() -> [URL] {
        let cs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library").appendingPathComponent("CloudStorage")
        let items = (try? FileManager.default.contentsOfDirectory(
            at: cs, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// True if `path` lives under the configured recordings dir (replaces the old
    /// hardcoded "/Whisper Memory/recordings/" check, which broke once configurable).
    /// Note: a loose folder-name match — used only for UI labelling, never deletion.
    static func isRecording(path: String) -> Bool {
        URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent == "recordings"
    }

    /// #9 — strict check for destructive actions: the file is actually inside *our*
    /// recordings dir, not merely in some folder named "recordings" (which could be
    /// the user's own audio dragged in for transcription).
    static func isInRecordingsDir(_ path: String) -> Bool {
        URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL.path
            == recordingsDir.standardizedFileURL.path
    }

    /// #10 — a crash while recording leaves a (crash-safe, playable) WAV in the local
    /// staging dir where the user can't see it. At launch — with no recording in
    /// flight — move any non-empty leftovers into the recordings dir so they're
    /// recoverable, and drop empty (header-only) fragments.
    static func adoptOrphanedStagingRecordings() {
        adoptStaging(from: stagingDir, into: recordingsDir)
    }

    /// Testable core of the launch-time crash-recovery sweep (arbitrary dirs).
    static func adoptStaging(from stagingDir: URL, into dir: URL) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: stagingDir,
                                                 includingPropertiesForKeys: [.fileSizeKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        for f in files {
            // Only the WAV is recoverable; a crash-orphaned .mp4 was never finalized
            // (no moov atom) so it's unplayable — drop it instead of cluttering output.
            guard f.pathExtension.lowercased() == "wav" else { try? fm.removeItem(at: f); continue }
            // Delete only when we KNOW it's an empty header-only fragment; on a failed
            // size read, err toward keeping the file (move it), never deleting it.
            if let size = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 44 {
                try? fm.removeItem(at: f)
            } else {
                try? fm.moveItem(at: f, to: uniqueDestination(in: dir, filename: f.lastPathComponent))
            }
        }
    }

    private static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
