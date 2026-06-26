import SwiftUI
import AppKit

/// Custom shell matching the redesign: dark sidebar with blue-filled selection +
/// a 52px top bar. Used with `.windowStyle(.hiddenTitleBar)` so the native traffic
/// lights sit in the sidebar's top-left corner (kept clear).
struct RootView: View {
    enum Section: String, CaseIterable, Identifiable {
        case record = "Enregistrer"
        case transcribe = "Transcrire"
        case history = "Historique"
        case logs = "Journaux"
        case settings = "Réglages"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .record: return "record.circle"
            case .transcribe: return "waveform"
            case .history: return "clock"
            case .logs: return "text.alignleft"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    @State private var selection: Section = .transcribe
    @Environment(TranscriptionManager.self) private var manager
    @Environment(RecordingService.self) private var recorder
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                topBar
                detail
            }
        }
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .frame(minWidth: 940, minHeight: 620)
        .onAppear {
            manager.modelContext = context
            recorder.transcriptionManager = manager
            AppLog.shared.modelContext = context
            AppLog.shared.prune()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            Task { await recorder.handleSystemWillSleep() }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 3) {
            Color.clear.frame(height: 52)           // native traffic-light area
            ForEach(Section.allCases) { sidebarRow($0) }
            Spacer()
            if recorder.state == .recording || recorder.state == .paused { recordingPill }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: 220)
        .background(Theme.bar)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderSubtle).frame(width: 1) }
    }

    private func sidebarRow(_ item: Section) -> some View {
        let selected = selection == item
        return Button { selection = item } label: {
            HStack(spacing: 11) {
                Image(systemName: item.icon).frame(width: 18, height: 18)
                Text(item.rawValue).font(.system(size: 14.5, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(selected ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(selected ? .white : Color(hex: 0xC7C7CC))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recordingPill: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.red).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(timeString(recorder.elapsed))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.red)
                Text("en cours d'enregistrement").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(11)
        .background(Theme.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.red.opacity(0.2), lineWidth: 1))
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Text(selection.rawValue).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            statusIndicator
        }
        .padding(.horizontal, 22)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if recorder.state == .recording || recorder.state == .paused {
            HStack(spacing: 7) {
                Circle().fill(Theme.red).frame(width: 7, height: 7)
                Text("Enregistrement").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.red)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(Theme.red.opacity(0.15), in: Capsule())
        } else if selection == .record {
            HStack(spacing: 7) {
                Circle().fill(Theme.textSecondary).frame(width: 7, height: 7)
                Text("Inactif").font(.system(size: 12.5))
            }
            .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        Group {
            switch selection {
            case .record:     RecordView()
            case .transcribe: TranscribeView()
            case .history:    HistoryView()
            case .logs:       LogsView()
            case .settings:   SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

/// Menu-bar content with recording controls.
struct MenuBarView: View {
    @Environment(TranscriptionManager.self) private var manager
    @Environment(RecordingService.self) private var recorder

    var body: some View {
        let running = manager.runs.values.filter { $0.status == .running }.count
        VStack(alignment: .leading, spacing: 6) {
            Text("WhisperBox").font(.headline)
            switch recorder.state {
            case .recording:
                Text("🔴 Enregistrement · \(timeString(recorder.elapsed))").font(.callout)
                Button("Pause") { recorder.pause() }
                Button("Arrêter") { Task { await recorder.stopAndTranscribe() } }
            case .paused:
                Text("⏸︎ En pause · \(timeString(recorder.elapsed))").font(.callout)
                Button("Reprendre") { recorder.resume() }
                Button("Arrêter") { Task { await recorder.stopAndTranscribe() } }
            default:
                Button("Démarrer l'enregistrement") { Task { try? await recorder.start(captureSystem: true, captureMic: true) } }
            }
            if running > 0 {
                Text("\(running) transcription(s) en cours").foregroundStyle(.secondary).font(.caption)
            }
            Divider()
            Button("Quitter") { NSApplication.shared.terminate(nil) }
        }
        .padding(8)
        .frame(width: 240)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
