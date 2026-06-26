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
        guard !filePath.isEmpty else { return "Choisissez un fichier audio ou vidéo" }
        let size = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int)
            .flatMap { $0 }.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        return [size, filePath].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcrire un fichier").font(.system(size: 22, weight: .bold))
                    Text("La transcription continue même si vous changez d'onglet — suivez la progression dans l'Historique.")
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
                    Text(fileName.isEmpty ? "Aucun fichier" : fileName).font(.system(size: 14.5, weight: .semibold))
                    Text(fileMeta).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Parcourir…") { showImporter = true }.buttonStyle(SecondaryButton())
                Button("Transcrire") { activeJobID = manager.start(filePath: filePath) }
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
                        Button("Annuler") { manager.cancel(jid) }.buttonStyle(DestructiveButton())
                    }
                }
            }
        }
    }

    private func columns(_ run: TranscriptionManager.RunState) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 0) {
                HStack {
                    Text("Aperçu en direct").font(.system(size: 13, weight: .semibold))
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
            Button { manager.enhance(jobID: jid) } label: { Label("Résumé Claude", systemImage: "sparkles") }
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
        if r.preparingModel { return "Préparation du modèle… (1er lancement)" }
        switch r.status {
        case .running:   return "Transcription en cours…"
        case .success:   return "Terminé — \(r.segments.count) segments"
        case .error:     return "Erreur"
        case .cancelled: return "Annulé"
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
                    Text("Prêt à enregistrer").font(.system(size: 21, weight: .semibold))
                    Text("Capture l'audio du système et du micro — transcription locale")
                        .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                }
            }

            Card(padding: 0) {
                VStack(spacing: 0) {
                    ToggleRow(title: "Inclure l'audio système",
                              subtitle: "Capture le son de l'ordinateur (requiert l'autorisation d'enregistrement de l'écran)",
                              isOn: $captureSystem)
                    Rectangle().fill(Theme.border).frame(height: 1)
                    ToggleRow(title: "Inclure le micro",
                              subtitle: "Enregistre votre voix", isOn: $captureMic)
                    Rectangle().fill(Theme.border).frame(height: 1)
                    ToggleRow(title: "Transcription en direct",
                              subtitle: "Affiche le texte pendant l'enregistrement", isOn: $recorder.liveEnabled)
                }
            }
            .frame(width: 444)

            HStack(spacing: 10) {
                if captureSystem { Chip(label: "Sortie système", dot: Theme.accent) }
                if captureMic { Chip(label: "Micro intégré", dot: Theme.accent) }
            }

            if let err = startError ?? recorder.lastError {
                Text(err).foregroundStyle(Theme.redDim).font(.system(size: 12.5))
            } else if recorder.state == .endedBySleep {
                Text("Dernier enregistrement arrêté (veille) — fichier conservé.")
                    .foregroundStyle(Theme.textSecondary).font(.system(size: 12.5))
            } else {
                HStack(spacing: 8) {
                    Text("Astuce — appuyez sur")
                    Text("⌘R").font(.system(size: 11.5, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.control, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                        .foregroundStyle(Color(hex: 0xD6D6DA))
                    Text("pour démarrer")
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
                Text(recorder.state == .paused ? "EN PAUSE" : "ENREGISTREMENT EN COURS")
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
                        Button { recorder.resume() } label: { Label("Reprendre", systemImage: "play.fill") }
                            .buttonStyle(SecondaryButton())
                    }
                    Button { Task { await recorder.stopAndTranscribe() } } label: {
                        Label("Arrêter", systemImage: "stop.fill")
                    }
                    .buttonStyle(PrimaryButton())
                    .tint(Theme.red)
                }
                HStack(spacing: 9) {
                    if captureMic { Chip(label: "Micro inclus", dot: Theme.green) }
                    if recorder.liveEnabled { Chip(label: "Transcription en direct", dot: Theme.accent) }
                }
            }
            .padding(.top, 30)

            if recorder.liveEnabled {
                LivePanel(title: "Transcription en direct", live: recorder.state == .recording,
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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !running.isEmpty {
                    VStack(alignment: .leading, spacing: 11) {
                        SectionLabel(text: "En cours")
                        ForEach(running) { runningCard($0) }
                    }
                }
                VStack(alignment: .leading, spacing: 11) {
                    SectionLabel(text: "Terminés")
                    if done.isEmpty {
                        Text("Aucune transcription terminée")
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
                ContentUnavailableView("Aucune transcription", systemImage: "clock.arrow.circlepath")
            }
        }
        .sheet(item: $selected) { JobDetailView(job: $0) }
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
                        Text("En cours · \(job.createdAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    StatusBadge(status: .running)
                    Button("Annuler") { manager.cancel(job.id) }.buttonStyle(DestructiveButton())
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
        job.sourcePath.contains("/Whisper Memory/recordings/")
    }

    @ViewBuilder
    private func menu(_ job: TranscriptionJob) -> some View {
        Button("Voir le détail") { selected = job }
        if let p = job.outputPath {
            Button("Ouvrir la transcription") { open(p) }
            Button("Afficher dans le Finder") { reveal(p) }
        }
        Button(isFromRecording(job) ? "Ouvrir l'enregistrement" : "Ouvrir l'audio source") {
            open(job.sourcePath)
        }
        if let s = job.summaryPath { Button("Ouvrir le résumé") { open(s) } }
        Divider()
        if job.outputPath != nil || !job.transcriptText.isEmpty {
            Button("Exporter la transcription…") {
                let base = URL(fileURLWithPath: job.sourcePath).deletingPathExtension().lastPathComponent
                if let p = job.outputPath {
                    Exporter.saveCopy(of: p, suggestedName: URL(fileURLWithPath: p).lastPathComponent)
                } else {
                    Exporter.save(text: job.transcriptText, suggestedName: "\(base).txt")
                }
            }
        }
        if let s = job.summaryPath {
            Button("Exporter le résumé…") {
                Exporter.saveCopy(of: s, suggestedName: URL(fileURLWithPath: s).lastPathComponent)
            }
        }
        if !job.transcriptText.isEmpty { Button("Résumé Claude") { manager.enhance(jobID: job.id) } }
        Button("Re-transcrire (haute qualité)") { manager.start(filePath: job.sourcePath) }
        Divider()
        Button("Supprimer", role: .destructive) { context.delete(job); try? context.save() }
    }

    private func open(_ path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// Detail sheet — read the full transcript + summary, with actions.
struct JobDetailView: View {
    let job: TranscriptionJob
    @Environment(TranscriptionManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    private var summaryText: String? {
        if let e = manager.enhancements[job.id], !e.text.isEmpty { return e.text }
        if let p = job.summaryPath { return try? String(contentsOfFile: p, encoding: .utf8) }
        return nil
    }

    @State private var tab = 0
    @State private var selectedLog: ExecutionLog?
    private var isRecording: Bool { job.sourcePath.contains("/Whisper Memory/recordings/") }
    private var base: String { URL(fileURLWithPath: job.sourcePath).deletingPathExtension().lastPathComponent }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(job.sourceFilename).font(.system(size: 17, weight: .bold)).lineLimit(1)
                    HStack(spacing: 9) {
                        Text(job.createdAt.formatted(date: .long, time: .shortened))
                            .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                        if isRecording {
                            Text("Enregistrement").font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 9).padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.14), in: Capsule()).foregroundStyle(Theme.accentText)
                        }
                        StatusBadge(status: job.status)
                    }
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }
                    .buttonStyle(.plain).frame(width: 28, height: 28)
                    .background(Theme.control, in: Circle()).foregroundStyle(Theme.gray)
            }
            .padding(18)

            // Tabs
            HStack(spacing: 4) {
                tabButton("Transcription", 0)
                tabButton("Résumé Claude", 1)
                tabButton("Journaux", 2)
                Spacer()
            }
            .padding(.horizontal, 22)
            Rectangle().fill(Theme.border).frame(height: 1)

            // Body
            ScrollView {
                if tab == 2 {
                    let sorted = job.logs.sorted { $0.createdAt > $1.createdAt }
                    VStack(spacing: 8) {
                        if sorted.isEmpty {
                            Text("Aucun journal pour cette tâche.")
                                .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(sorted) { log in
                                Button { selectedLog = log } label: { Card(padding: 12) { LogRow(log: log) } }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 22).padding(.vertical, 16)
                } else {
                    Group {
                        if tab == 0 {
                            Text(job.transcriptText.isEmpty ? "(transcription vide)" : job.transcriptText)
                                .textSelection(.enabled)
                        } else if manager.enhancements[job.id]?.running == true {
                            HStack(spacing: 9) {
                                ProgressView().controlSize(.small)
                                Text("Génération du résumé…").foregroundStyle(Theme.textSecondary)
                            }
                        } else if let err = manager.enhancements[job.id]?.error {
                            Text(err).foregroundStyle(Theme.redDim)
                        } else {
                            Text(summaryText ?? "Aucun résumé — cliquez sur « Résumé Claude » ci-dessous.")
                                .textSelection(.enabled)
                        }
                    }
                    .font(.system(size: 14)).lineSpacing(3).foregroundStyle(Theme.bodyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.vertical, 16)
                }
            }
            .sheet(item: $selectedLog) { LogDetailSheet(log: $0) }

            // Action bar
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 8) {
                Menu {
                    Button("Transcription") {
                        if let p = job.outputPath { Exporter.saveCopy(of: p, suggestedName: URL(fileURLWithPath: p).lastPathComponent) }
                        else { Exporter.save(text: job.transcriptText, suggestedName: "\(base).txt") }
                    }
                    if summaryText != nil { Button("Résumé") { Exporter.save(text: summaryText ?? "", suggestedName: "\(base).summary.md") } }
                } label: { Label("Exporter", systemImage: "square.and.arrow.down") }
                    .menuStyle(.button).buttonStyle(SecondaryButton()).fixedSize()

                Button("Ouvrir") { if let p = job.outputPath { NSWorkspace.shared.open(URL(fileURLWithPath: p)) } }
                    .buttonStyle(SecondaryButton()).disabled(job.outputPath == nil)
                Button("Révéler dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: job.outputPath ?? job.sourcePath)])
                }.buttonStyle(SecondaryButton())
                Button("Re-transcrire (HQ)") { manager.start(filePath: job.sourcePath); dismiss() }
                    .buttonStyle(SecondaryButton())
                Spacer()
                Button { tab = 1; manager.enhance(jobID: job.id) } label: { Label("Résumé Claude", systemImage: "sparkles") }
                    .buttonStyle(PrimaryButton())
                    .disabled(manager.enhancements[job.id]?.running == true || job.transcriptText.isEmpty)
            }
            .padding(.horizontal, 22).padding(.vertical, 13)
            .background(Theme.window)
        }
        .frame(width: 660, height: 560)
        .background(Theme.sheet)
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
                        Text("Tâche : \(j.sourceFilename)").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
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
                    Button("Tous les niveaux") { levelFilter = nil }
                    Divider()
                    ForEach(LogLevel.allCases, id: \.self) { lvl in
                        Button(lvl.rawValue.capitalized) { levelFilter = lvl }
                    }
                } label: {
                    Label(levelFilter?.rawValue.capitalized ?? "Tous les niveaux",
                          systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.button).buttonStyle(SecondaryButton()).fixedSize()
                Spacer()
                Button("Exporter") { Exporter.save(text: exportText(), suggestedName: "whisperbox-journaux.log") }
                    .buttonStyle(SecondaryButton()).disabled(logs.isEmpty)
                Button("Vider", role: .destructive) { AppLog.shared.clearAll() }
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
                ContentUnavailableView("Aucun journal", systemImage: "text.alignleft")
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
                    row("Modèle") {
                        HStack(spacing: 6) {
                            Text("large-v3-turbo").foregroundStyle(Theme.textSecondary)
                            Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    divider
                    row("Langue") {
                        Picker("", selection: $s.defaultLanguage) {
                            Text("Détection auto").tag("")
                            Text("Français").tag("fr")
                            Text("English").tag("en")
                            Text("Español").tag("es")
                            Text("Deutsch").tag("de")
                        }.labelsHidden().frame(width: 160)
                    }
                    divider
                    row("Format de sortie") {
                        Picker("", selection: $s.defaultOutputFormat) {
                            Text("Texte").tag("txt"); Text("SRT").tag("srt"); Text("VTT").tag("vtt")
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                    }
                }

                group("Amélioration Claude") {
                    toggleRow("Activer l'amélioration Claude",
                              "Résume automatiquement les transcriptions avec Claude", $s.claudeEnabled)
                    divider
                    row("Modèle") {
                        Picker("", selection: $s.claudeModel) {
                            Text("Opus 4.8").tag("claude-opus-4-8")
                            Text("Sonnet 4.6").tag("claude-sonnet-4-6")
                            Text("Haiku 4.5").tag("claude-haiku-4-5-20251001")
                        }.labelsHidden().frame(width: 160)
                    }
                    divider
                    toggleRow("Résumé automatique après transcription", "", $s.claudeAutoAfterTranscribe)
                }

                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel(text: "Prompt Claude")
                    Text("Cette instruction est envoyée à Claude, suivie de la transcription.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    Card(background: Theme.panel) {
                        VStack(alignment: .trailing, spacing: 8) {
                            TextEditor(text: $s.claudePrompt)
                                .font(.system(size: 13, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120)
                            Button("Réinitialiser") { s.claudePrompt = EnhancementService.defaultPrompt }
                                .buttonStyle(SecondaryButton())
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        SectionLabel(text: "Jeton Claude")
                        Spacer()
                        if EnhancementService.isAvailable {
                            Label("CLI claude détecté", systemImage: "checkmark.seal.fill")
                                .font(.system(size: 11)).foregroundStyle(Theme.green)
                        } else {
                            Label("CLI claude introuvable", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11)).foregroundStyle(Theme.redDim)
                        }
                    }
                    Text("Si le CLI claude est déjà connecté, laissez vide. Sinon, collez un token OAuth.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    if !EnhancementService.isAvailable {
                        Text("1. Installez le CLI :  npm install -g @anthropic-ai/claude-code")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary).textSelection(.enabled)
                    }
                    Text("Pour générer un token : lancez «\u{00a0}claude setup-token\u{00a0}» dans le Terminal, puis collez-le ci-dessous. (Ou lancez «\u{00a0}claude\u{00a0}» une fois pour vous connecter — aucun token requis.)")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary).textSelection(.enabled)
                    Card {
                        VStack(spacing: 10) {
                            SecureField("CLAUDE_CODE_OAUTH_TOKEN", text: $token).textFieldStyle(.roundedBorder)
                            HStack {
                                Button("Enregistrer") { if !token.isEmpty { KeychainService.set(token); token = "" } }
                                    .buttonStyle(SecondaryButton()).disabled(token.isEmpty)
                                Button("Effacer") { KeychainService.delete() }.buttonStyle(SecondaryButton())
                                Spacer()
                                if KeychainService.get() != nil {
                                    Label("token présent", systemImage: "checkmark.seal.fill")
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
