import SwiftUI
import SwiftData

/// App entry point. Single SwiftUI process — no server, no localhost, no Python.
@main
struct WhisperBoxApp: App {
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

    private func shortTime(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(manager)
                .environment(recorder)
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
                            try? await recorder.start(captureSystem: true, captureMic: true)
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
            if recorder.state == .recording {
                Label(shortTime(recorder.elapsed), systemImage: "waveform")
            } else {
                Image(systemName: "waveform")
            }
        }
        .modelContainer(container)
    }
}
