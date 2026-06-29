import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

// Phase 1 placeholders — structure + navigation only. Each is fleshed out in
// its phase: Transcribe (P2), Record (P3), Settings (P1/P4), History/Logs (P6).

struct TranscribeView: View {
    @Environment(TranscriptionManager.self) private var manager
    @State private var filePath = ""
    @State private var showImporter = false
    @State private var activeJobID: UUID?

    private var run: TranscriptionManager.RunState? {
        activeJobID.flatMap { manager.runs[$0] }
    }

    private var fileName: String { filePath.isEmpty ? "" : URL(fileURLWithPath: filePath).lastPathComponent }
    private var fileMeta: String {
        guard !filePath.isEmpty else { return "Choose an audio or video file" }
        let size = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int)
            .flatMap { $0 }.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        return [size, filePath].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcribe a file").font(.system(size: 22, weight: .bold))
                    Text("Transcription continues even if you switch tabs — track progress in History.")
                        .font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
                }
                fileCard
                if let run {
                    progressCard(run)
                    columns(run)
                    if run.status == .success, let jid = activeJobID { enhancementSection(jid) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 34).padding(.vertical, 30)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.audio, .movie, .mpeg4Movie],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first { filePath = u.path }
        }
    }

    private var fileCard: some View {
        Card {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 9).fill(Theme.accent.opacity(0.14)).frame(width: 42, height: 42)
                    .overlay(Image(systemName: "doc.text").foregroundStyle(Theme.accentText))
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName.isEmpty ? "No file" : fileName).font(.system(size: 14.5, weight: .semibold))
                    Text(fileMeta).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Browse…") { showImporter = true }.buttonStyle(SecondaryButton())
                Button("Transcribe") { activeJobID = manager.start(filePath: filePath) }
                    .buttonStyle(PrimaryButton())
                    .disabled(filePath.isEmpty || run?.status == .running)
            }
        }
    }

    private func progressCard(_ run: TranscriptionManager.RunState) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 9) {
                        if run.status == .running { ProgressView().controlSize(.small) }
                        Text(statusText(run)).font(.system(size: 14, weight: .medium))
                    }
                    Spacer()
                    if !run.preparingModel {
                        Text("\(Int(run.progress * 100)) %")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.accentText)
                    }
                }
                if run.preparingModel {
                    ProgressView().progressViewStyle(.linear).tint(Theme.accent)
                } else {
                    ProgressView(value: run.progress).tint(Theme.accent)
                }
                HStack {
                    Text("\(run.segments.count) segments · large-v3-turbo")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if run.status == .running, let jid = activeJobID {
                        Button("Cancel") { manager.cancel(jid) }.buttonStyle(DestructiveButton())
                    }
                }
            }
        }
    }

    private func columns(_ run: TranscriptionManager.RunState) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 0) {
                HStack {
                    Text("Live preview").font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 15).padding(.vertical, 11)
                Rectangle().fill(Theme.border).frame(height: 1)
                ScrollView {
                    Text(run.liveText.isEmpty ? "…" : run.liveText)
                        .font(.system(size: 13.5)).foregroundStyle(Color(hex: 0xC7C7CC))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 15).padding(.vertical, 13)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border, lineWidth: 1))

            LivePanel(title: "Segments", caption: "", segments: run.segments).frame(width: 330)
        }
        .frame(height: 240)
    }

    @ViewBuilder
    private func enhancementSection(_ jid: UUID) -> some View {
        let e = manager.enhancements[jid]
        HStack {
            Button { manager.enhance(jobID: jid) } label: { Label("Claude Summary", systemImage: "sparkles") }
                .buttonStyle(PrimaryButton())
                .disabled(e?.running == true)
            if e?.running == true { ProgressView().controlSize(.small) }
            Spacer()
        }
        if let e {
            if let err = e.error {
                Text(err).foregroundStyle(Theme.redDim).font(.system(size: 12.5))
            } else if !e.text.isEmpty {
                Card(background: Theme.panel) {
                    ScrollView { Text(e.text).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 160)
                }
            }
        }
    }

    private func statusText(_ r: TranscriptionManager.RunState) -> String {
        if r.preparingModel { return "Preparing model… (first launch)" }
        switch r.status {
        case .running:   return "Transcribing…"
        case .success:   return "Done — \(r.segments.count) segments"
        case .error:     return "Error"
        case .cancelled: return "Cancelled"
        default:         return ""
        }
    }
}

struct RecordView: View {
    @Environment(RecordingService.self) private var recorder
    @State private var captureSystem = true
    @State private var captureMic = true
    @State private var startError: String?

    private var idle: Bool {
        recorder.state == .idle || recorder.state == .stopped || recorder.state == .endedBySleep
    }

    var body: some View {
        @Bindable var recorder = recorder
        if idle { idleView(recorder) } else { activeView }
    }

    private func idleView(_ recorder: RecordingService) -> some View {
        @Bindable var recorder = recorder
        return VStack(spacing: 26) {
            VStack(spacing: 18) {
                RecordButton { Task { await start() } }
                VStack(spacing: 6) {
                    Text("Ready to record").font(.system(size: 21, weight: .semibold))
                    Text("Captures system and microphone audio — local transcription")
                        .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                }
            }

            Card(padding: 0) {
                VStack(spacing: 0) {
                    ToggleRow(title: "Include system audio",
                              subtitle: "Captures the computer's sound (requires screen recording permission)",
                              isOn: $captureSystem)
                    Rectangle().fill(Theme.border).frame(height: 1)
                    ToggleRow(title: "Include microphone",
                              subtitle: "Records your voice", isOn: $captureMic)
                    Rectangle().fill(Theme.border).frame(height: 1)
                    ToggleRow(title: "Live transcription",
                              subtitle: "Shows text while recording", isOn: $recorder.liveEnabled)
                }
            }
            .frame(width: 444)

            HStack(spacing: 10) {
                if captureSystem { Chip(label: "System output", dot: Theme.accent) }
                if captureMic { Chip(label: "Built-in mic", dot: Theme.accent) }
            }

            if let err = startError ?? recorder.lastError {
                Text(err).foregroundStyle(Theme.redDim).font(.system(size: 12.5))
            } else if recorder.state == .endedBySleep {
                Text("Last recording stopped (sleep) — file kept.")
                    .foregroundStyle(Theme.textSecondary).font(.system(size: 12.5))
            } else {
                HStack(spacing: 8) {
                    Text("Tip — press")
                    Text("⌘R").font(.system(size: 11.5, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.control, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                        .foregroundStyle(Color(hex: 0xD6D6DA))
                    Text("to start")
                }
                .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var activeView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Text(recorder.state == .paused ? "PAUSED" : "RECORDING")
                    .font(.system(size: 11.5, weight: .semibold)).tracking(1.8)
                    .foregroundStyle(Theme.red)
                Text(timeString(recorder.elapsed))
                    .font(.system(size: 58, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.red)
                Waveform().frame(width: 520).opacity(recorder.state == .recording ? 1 : 0.3)
                HStack(spacing: 12) {
                    if recorder.state == .recording {
                        Button { recorder.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                            .buttonStyle(SecondaryButton())
                    } else {
                        Button { recorder.resume() } label: { Label("Resume", systemImage: "play.fill") }
                            .buttonStyle(SecondaryButton())
                    }
                    Button { Task { await recorder.stopAndTranscribe() } } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(PrimaryButton())
                    .tint(Theme.red)
                }
                HStack(spacing: 9) {
                    if captureMic { Chip(label: "Mic included", dot: Theme.green) }
                    if recorder.liveEnabled { Chip(label: "Live transcription", dot: Theme.accent) }
                }
            }
            .padding(.top, 30)

            if recorder.liveEnabled {
                LivePanel(title: "Live transcription", live: recorder.state == .recording,
                          segments: recorder.live.segments,
                          unconfirmedCount: recorder.live.unconfirmedSegments.count)
                    .padding(.top, 22)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 34).padding(.bottom, 26)
    }

    private func start() async {
        startError = nil
        do { try await recorder.start(captureSystem: captureSystem, captureMic: captureMic) }
        catch { startError = error.localizedDescription }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

struct HistoryView: View {
    @Environment(TranscriptionManager.self) private var manager
    @Environment(\.modelContext) private var context
    @Query(sort: \TranscriptionJob.createdAt, order: .reverse) private var jobs: [TranscriptionJob]
    @State private var selected: TranscriptionJob?

    private func isRunning(_ job: TranscriptionJob) -> Bool { manager.runs[job.id]?.status == .running }
    private var running: [TranscriptionJob] { jobs.filter(isRunning) }
    private var done: [TranscriptionJob] { jobs.filter { !isRunning($0) } }

    var body: some View {
        if let selected {
            JobDetailView(job: selected) { self.selected = nil }
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !running.isEmpty {
                    VStack(alignment: .leading, spacing: 11) {
                        SectionLabel(text: "In progress")
                        ForEach(running) { runningCard($0) }
                    }
                }
                VStack(alignment: .leading, spacing: 11) {
                    SectionLabel(text: "Completed")
                    if done.isEmpty {
                        Text("No completed transcriptions")
                            .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    } else {
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(done.enumerated()), id: \.element.id) { i, job in
                                    doneRow(job)
                                    if i < done.count - 1 { Rectangle().fill(Theme.border).frame(height: 1) }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 34).padding(.vertical, 26)
        }
        .overlay {
            if jobs.isEmpty {
                ContentUnavailableView("No transcriptions", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private func iconBox(_ job: TranscriptionJob, error: Bool = false) -> some View {
        let rec = isFromRecording(job)
        return RoundedRectangle(cornerRadius: 9)
            .fill(error ? Theme.control : Theme.accent.opacity(0.13))
            .frame(width: 38, height: 38)
            .overlay(Image(systemName: rec ? "mic.fill" : "doc.text")
                .foregroundStyle(error ? Theme.gray : Theme.accentText))
    }

    @ViewBuilder
    private func runningCard(_ job: TranscriptionJob) -> some View {
        let r = manager.runs[job.id]
        Card(padding: 16) {
            VStack(spacing: 11) {
                HStack(spacing: 13) {
                    iconBox(job)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.sourceFilename).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text("In progress · \(job.createdAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    StatusBadge(status: .running)
                    Button("Cancel") { manager.cancel(job.id) }.buttonStyle(DestructiveButton())
                }
                HStack(spacing: 12) {
                    ProgressView(value: r?.progress ?? 0).tint(Theme.accent)
                    Text("\(Int((r?.progress ?? 0) * 100)) %")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accentText)
                }
                if let live = r?.liveText, !live.isEmpty {
                    Text("…\(String(live.suffix(120)))")
                        .font(.system(size: 12)).italic().foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private func doneRow(_ job: TranscriptionJob) -> some View {
        Button { selected = job } label: {
            HStack(spacing: 13) {
                iconBox(job, error: job.status == .error)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.sourceFilename).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    if job.status == .error, let e = job.errorMessage {
                        Text(e).font(.system(size: 12)).foregroundStyle(Theme.redDim).lineLimit(1)
                    } else {
                        Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                StatusBadge(status: job.status)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 17).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menu(job) }
    }

    private func isFromRecording(_ job: TranscriptionJob) -> Bool {
        AppPaths.isRecording(path: job.sourcePath)
    }

    @ViewBuilder
    private func menu(_ job: TranscriptionJob) -> some View {
        Button("View details") { selected = job }
        if let p = job.outputPath {
            Button("Open transcription") { open(p) }
            Button("Show in Finder") { reveal(p) }
        }
        Button(isFromRecording(job) ? "Open recording" : "Open source audio") {
            open(job.sourcePath)
        }
        if let s = job.summaryPath { Button("Open summary") { open(s) } }
        Divider()
        if job.outputPath != nil || !job.transcriptText.isEmpty {
            Button("Export transcription…") {
                let base = URL(fileURLWithPath: job.sourcePath).deletingPathExtension().lastPathComponent
                if let p = job.outputPath {
                    Exporter.saveCopy(of: p, suggestedName: URL(fileURLWithPath: p).lastPathComponent)
                } else {
                    Exporter.save(text: job.transcriptText, suggestedName: "\(base).txt")
                }
            }
        }
        if let s = job.summaryPath {
            Button("Export summary…") {
                Exporter.saveCopy(of: s, suggestedName: URL(fileURLWithPath: s).lastPathComponent)
            }
        }
        if !job.transcriptText.isEmpty { Button("Claude Summary") { manager.enhance(jobID: job.id) } }
        Button("Re-transcribe (high quality)") { manager.start(filePath: job.sourcePath) }
        Divider()
        Button("Delete", role: .destructive) { context.delete(job); try? context.save() }
    }

    private func open(_ path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// Full-page detail — read the full transcript + summary, with actions.
/// Replaces the History list in place; `onBack` returns to the list.
struct JobDetailView: View {
    let job: TranscriptionJob
    let onBack: () -> Void
    @Environment(TranscriptionManager.self) private var manager

    private var summaryText: String? {
        if let e = manager.enhancements[job.id], !e.text.isEmpty { return e.text }
        if let p = job.summaryPath { return try? String(contentsOfFile: p, encoding: .utf8) }
        return nil
    }

    @State private var tab = 0
    @State private var selectedLog: ExecutionLog?
    private var isRecording: Bool { AppPaths.isRecording(path: job.sourcePath) }
    private var base: String { URL(fileURLWithPath: job.sourcePath).deletingPathExtension().lastPathComponent }

    private var durationText: String? {
        guard let d = job.durationAudio, d > 0 else { return nil }
        let s = Int(d.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — back button + title + meta
            VStack(alignment: .leading, spacing: 16) {
                Button(action: onBack) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text("History").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.accentText)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 7) {
                    Text(job.sourceFilename).font(.system(size: 20, weight: .bold)).lineLimit(1)
                    HStack(spacing: 9) {
                        Text(job.createdAt.formatted(date: .long, time: .shortened))
                            .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                        if let durationText {
                            Text("·").foregroundStyle(Theme.textTertiary)
                            Text(durationText).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                        }
                        if isRecording {
                            Text("Recording").font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 9).padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.14), in: Capsule()).foregroundStyle(Theme.accentText)
                        }
                        StatusBadge(status: job.status)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 34).padding(.top, 22).padding(.bottom, 18)

            // Tabs
            HStack(spacing: 4) {
                tabButton("Transcription", 0)
                tabButton("Claude Summary", 1)
                tabButton("Logs", 2)
                Spacer()
            }
            .padding(.horizontal, 34)
            Rectangle().fill(Theme.border).frame(height: 1)

            // Body
            ScrollView {
                if tab == 2 {
                    let sorted = job.logs.sorted { $0.createdAt > $1.createdAt }
                    VStack(spacing: 8) {
                        if sorted.isEmpty {
                            Text("No logs for this job.")
                                .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(sorted) { log in
                                Button { selectedLog = log } label: { Card(padding: 12) { LogRow(log: log) } }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 34).padding(.vertical, 18)
                } else {
                    Group {
                        if tab == 0 {
                            Text(job.transcriptText.isEmpty ? "(empty transcription)" : job.transcriptText)
                                .textSelection(.enabled)
                        } else if manager.enhancements[job.id]?.running == true {
                            HStack(spacing: 9) {
                                ProgressView().controlSize(.small)
                                Text("Generating summary…").foregroundStyle(Theme.textSecondary)
                            }
                        } else if let err = manager.enhancements[job.id]?.error {
                            Text(err).foregroundStyle(Theme.redDim)
                        } else {
                            Text(summaryText ?? "No summary — click \u{201c}Claude Summary\u{201d} below.")
                                .textSelection(.enabled)
                        }
                    }
                    .font(.system(size: 14)).lineSpacing(3).foregroundStyle(Theme.bodyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 34).padding(.vertical, 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(item: $selectedLog) { LogDetailSheet(log: $0) }

            // Action bar
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 8) {
                Menu {
                    Button("Transcription") {
                        if let p = job.outputPath { Exporter.saveCopy(of: p, suggestedName: URL(fileURLWithPath: p).lastPathComponent) }
                        else { Exporter.save(text: job.transcriptText, suggestedName: "\(base).txt") }
                    }
                    if summaryText != nil { Button("Summary") { Exporter.save(text: summaryText ?? "", suggestedName: "\(base).summary.md") } }
                } label: { Label("Export", systemImage: "square.and.arrow.down") }
                    .menuStyle(.button).buttonStyle(SecondaryButton()).fixedSize()

                Button("Open") { if let p = job.outputPath { NSWorkspace.shared.open(URL(fileURLWithPath: p)) } }
                    .buttonStyle(SecondaryButton()).disabled(job.outputPath == nil)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: job.outputPath ?? job.sourcePath)])
                }.buttonStyle(SecondaryButton())
                Button("Re-transcribe (HQ)") { manager.start(filePath: job.sourcePath); onBack() }
                    .buttonStyle(SecondaryButton())
                Spacer()
                Button { tab = 1; manager.enhance(jobID: job.id) } label: { Label("Claude Summary", systemImage: "sparkles") }
                    .buttonStyle(PrimaryButton())
                    .disabled(manager.enhancements[job.id]?.running == true || job.transcriptText.isEmpty)
            }
            .padding(.horizontal, 34).padding(.vertical, 13)
            .background(Theme.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
    }

    private func tabButton(_ title: String, _ index: Int) -> some View {
        Button { tab = index } label: {
            Text(title)
                .font(.system(size: 13, weight: tab == index ? .semibold : .medium))
                .foregroundStyle(tab == index ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(tab == index ? Theme.accent : .clear).frame(height: 2)
                }
        }
        .buttonStyle(.plain)
    }
}

/// Export helpers — save transcript/summary to a user-chosen location.
enum Exporter {
    @MainActor
    static func save(text: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    static func saveCopy(of path: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.removeItem(at: url)            // overwrite if exists
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: url)
    }
}

/// Colored pill for a log level (matches StatusBadge styling).
struct LogLevelBadge: View {
    let level: LogLevel
    private var color: Color {
        switch level {
        case .error:   return Theme.red
        case .warning: return .orange
        case .success: return Theme.green
        case .info:    return Theme.accent
        case .debug:   return Theme.gray
        }
    }
    var body: some View {
        Text(level.rawValue.uppercased())
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

/// One log entry as a card row (used in the Logs tab and the per-job tab).
struct LogRow: View {
    let log: ExecutionLog
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                LogLevelBadge(level: log.level)
                Text(log.operationType).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(log.createdAt.formatted(date: .numeric, time: .standard))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textTertiary)
            }
            Text(log.message).font(.system(size: 13.5)).foregroundStyle(Theme.bodyText)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let c = log.logContent, !c.isEmpty {
                Text(c).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Full detail of a single log entry.
struct LogDetailSheet: View {
    let log: ExecutionLog
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 9) {
                        LogLevelBadge(level: log.level)
                        Text(log.operationType).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    }
                    Text(log.createdAt.formatted(date: .long, time: .standard))
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }
                    .buttonStyle(.plain).frame(width: 28, height: 28)
                    .background(Theme.control, in: Circle()).foregroundStyle(Theme.gray)
            }
            .padding(18)
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(log.message).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    if let c = log.logContent, !c.isEmpty {
                        Text(c).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.bodyText)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let j = log.job {
                        Text("Job: \(j.sourceFilename)").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 420)
        .background(Theme.sheet)
    }
}

struct LogsView: View {
    @Query(sort: \ExecutionLog.createdAt, order: .reverse) private var logs: [ExecutionLog]
    @State private var levelFilter: LogLevel?
    @State private var selected: ExecutionLog?

    private var filtered: [ExecutionLog] {
        guard let levelFilter else { return logs }
        return logs.filter { $0.level == levelFilter }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Menu {
                    Button("All levels") { levelFilter = nil }
                    Divider()
                    ForEach(LogLevel.allCases, id: \.self) { lvl in
                        Button(lvl.rawValue.capitalized) { levelFilter = lvl }
                    }
                } label: {
                    Label(levelFilter?.rawValue.capitalized ?? "All levels",
                          systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.button).buttonStyle(SecondaryButton()).fixedSize()
                Spacer()
                Button("Export") { Exporter.save(text: exportText(), suggestedName: "whisperbox-logs.log") }
                    .buttonStyle(SecondaryButton()).disabled(logs.isEmpty)
                Button("Clear", role: .destructive) { AppLog.shared.clearAll() }
                    .buttonStyle(SecondaryButton()).disabled(logs.isEmpty)
            }
            .padding(.horizontal, 34).padding(.top, 22).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(filtered) { log in
                        Button { selected = log } label: { Card(padding: 13) { LogRow(log: log) } }
                            .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 34).padding(.bottom, 26)
            }
        }
        .overlay {
            if logs.isEmpty {
                ContentUnavailableView("No logs", systemImage: "text.alignleft")
            }
        }
        .sheet(item: $selected) { LogDetailSheet(log: $0) }
    }

    private func exportText() -> String {
        filtered.map { log in
            let ts = log.createdAt.formatted(date: .numeric, time: .standard)
            let head = "[\(ts)] \(log.level.rawValue.uppercased()) \(log.operationType): \(log.message)"
            if let c = log.logContent, !c.isEmpty { return head + "\n    " + c }
            return head
        }.joined(separator: "\n")
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var allSettings: [AppSettings]
    @State private var token = ""

    var body: some View {
        Group {
            if let s = allSettings.first {
                form(s)
            } else {
                Color.clear.onAppear { context.insert(AppSettings()); try? context.save() }
            }
        }
    }

    @ViewBuilder
    private func form(_ settings: AppSettings) -> some View {
        @Bindable var s = settings
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                group("Transcription") {
                    row("Model") {
                        HStack(spacing: 6) {
                            Text("large-v3-turbo").foregroundStyle(Theme.textSecondary)
                            Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    divider
                    row("Language") {
                        Picker("", selection: $s.defaultLanguage) {
                            Text("Auto-detect").tag("")
                            Text("French").tag("fr")
                            Text("English").tag("en")
                            Text("Spanish").tag("es")
                            Text("German").tag("de")
                        }.labelsHidden().frame(width: 160)
                    }
                    divider
                    row("Output format") {
                        Picker("", selection: $s.defaultOutputFormat) {
                            Text("Text").tag("txt"); Text("SRT").tag("srt"); Text("VTT").tag("vtt")
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                    }
                    divider
                    row("Output folder") {
                        HStack(spacing: 8) {
                            Text(displayPath(s.defaultOutputDir))
                                .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                                .lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: 200, alignment: .trailing)
                            Button("Choose…") { chooseOutputDir(s) }.buttonStyle(SecondaryButton())
                            if !s.defaultOutputDir.isEmpty {
                                Button("Reset") { s.defaultOutputDir = ""; AppPaths.setBase("") }
                                    .buttonStyle(SecondaryButton())
                            }
                        }
                    }
                }

                group("Claude Enhancement") {
                    toggleRow("Auto-summarize after transcription",
                              "Generate a Claude summary automatically after each transcription",
                              $s.claudeAutoAfterTranscribe)
                    divider
                    row("Model") {
                        Picker("", selection: $s.claudeModel) {
                            Text("Opus 4.8").tag("claude-opus-4-8")
                            Text("Sonnet 4.6").tag("claude-sonnet-4-6")
                            Text("Haiku 4.5").tag("claude-haiku-4-5-20251001")
                        }.labelsHidden().frame(width: 160)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel(text: "Claude Prompt")
                    Text("This instruction is sent to Claude, followed by the transcription.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    Card(background: Theme.panel) {
                        VStack(alignment: .trailing, spacing: 8) {
                            TextEditor(text: $s.claudePrompt)
                                .font(.system(size: 13, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120)
                            Button("Reset") { s.claudePrompt = EnhancementService.defaultPrompt }
                                .buttonStyle(SecondaryButton())
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        SectionLabel(text: "Claude Token")
                        Spacer()
                        if EnhancementService.isAvailable {
                            Label("claude CLI detected", systemImage: "checkmark.seal.fill")
                                .font(.system(size: 11)).foregroundStyle(Theme.green)
                        } else {
                            Label("claude CLI not found", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11)).foregroundStyle(Theme.redDim)
                        }
                    }
                    Text("If the claude CLI is already signed in, leave this empty. Otherwise, paste an OAuth token.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    if !EnhancementService.isAvailable {
                        Text("1. Install the CLI:  npm install -g @anthropic-ai/claude-code")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary).textSelection(.enabled)
                    }
                    Text("To generate a token: run \u{201c}\u{00a0}claude setup-token\u{00a0}\u{201d} in Terminal, then paste it below. (Or run \u{201c}\u{00a0}claude\u{00a0}\u{201d} once to sign in — no token required.)")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary).textSelection(.enabled)
                    Card {
                        VStack(spacing: 10) {
                            SecureField("CLAUDE_CODE_OAUTH_TOKEN", text: $token).textFieldStyle(.roundedBorder)
                            HStack {
                                Button("Save") { if !token.isEmpty { KeychainService.set(token); token = "" } }
                                    .buttonStyle(SecondaryButton()).disabled(token.isEmpty)
                                Button("Clear") { KeychainService.delete() }.buttonStyle(SecondaryButton())
                                Spacer()
                                if KeychainService.get() != nil {
                                    Label("token present", systemImage: "checkmark.seal.fill")
                                        .font(.system(size: 12)).foregroundStyle(Theme.green)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 34).padding(.vertical, 24)
        }
    }

    private func displayPath(_ p: String) -> String {
        p.isEmpty ? "~/Whisper Memory (default)" : (p as NSString).abbreviatingWithTildeInPath
    }

    private func chooseOutputDir(_ s: AppSettings) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        s.defaultOutputDir = url.path
        AppPaths.setBase(url.path)
    }

    private var divider: some View { Rectangle().fill(Theme.border).frame(height: 1) }

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: title)
            Card(padding: 0) { VStack(spacing: 0) { content() } }
        }
    }

    private func row<C: View>(_ title: String, @ViewBuilder trailing: () -> C) -> some View {
        HStack { Text(title).font(.system(size: 14)); Spacer(); trailing() }
            .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private func toggleRow(_ title: String, _ subtitle: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14))
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}
