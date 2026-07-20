import SwiftUI
import SwiftData
import AppKit

/// #22 — on Quit while recording, finalize the WAV before the process dies (otherwise
/// the RIFF header keeps `dataSize: 0` and the file plays as empty). The recorder is
/// registered from `RootView.onAppear`; termination is deferred until `stop()` returns.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var recorder: RecordingService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // #6 — don't let a broken pipe (e.g. the claude CLI exiting before it reads
        // stdin) raise SIGPIPE and kill the app; the write surfaces EPIPE instead.
        signal(SIGPIPE, SIG_IGN)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let rec = AppDelegate.recorder, rec.state == .recording || rec.state == .paused else {
            return .terminateNow
        }
        Task { @MainActor in
            await rec.stopForTermination()                     // finalize + persist, no unused tail pass
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// App entry point. Single SwiftUI process — no server, no localhost, no Python.
@main
struct WhisperBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// SwiftData container for jobs / logs / settings (local store in Application Support).
    let container: ModelContainer = {
        do {
            return try ModelContainer(for: TranscriptionJob.self, AppSettings.self, ExecutionLog.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    /// App-scoped — owns running transcriptions so they survive navigation.
    @State private var manager = TranscriptionManager()
    /// App-scoped — recording survives navigation too.
    @State private var recorder = RecordingService()
    /// #36 — emits a signal when a call likely starts (Core Audio mic-in-use edge).
    @State private var callDetector = CallDetector()

    private func shortTime(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(manager)
                .environment(recorder)
                .environment(callDetector)
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button(recorder.state == .recording || recorder.state == .paused
                       ? "Stop Recording" : "Start Recording") {
                    Task {
                        if recorder.state == .recording || recorder.state == .paused {
                            await recorder.stopAndTranscribe()
                        } else {
                            try? await recorder.startFromSettings()
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        // Menu-bar presence (replaces the Python rumps launcher).
        MenuBarExtra {
            MenuBarView()
                .environment(manager)
                .environment(recorder)
        } label: {
            switch recorder.state {
            case .recording:
                // #11 — red record glyph + elapsed time while capturing.
                Label {
                    Text(shortTime(recorder.elapsed))
                } icon: {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                }
            case .paused:
                Label(shortTime(recorder.elapsed), systemImage: "pause.circle")
            default:
                Image(systemName: "waveform")
            }
        }
        .modelContainer(container)
    }
}
