import Foundation
import SwiftData

// SwiftData models. Greenfield (no import from the old app.db, per decision).
// Includes the pause/sleep additions from SWIFT_MIGRATION_PLAN.md §10.4.

enum JobStatus: String, Codable {
    case pending, running, paused, success, error, cancelled
}

enum LogLevel: String, Codable, CaseIterable {
    case debug, info, success, warning, error
}

/// Persisted app event — revives the old backend's `execution_logs`. Feeds the
/// Logs tab and the per-job "Journaux" view; also mirrored to `os.Logger`.
/// `job` is optional (nil = app-level event) and cascades from `TranscriptionJob`.
@Model
final class ExecutionLog {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var levelRaw: String = LogLevel.info.rawValue
    var operationType: String = "app"   // app | recording | transcription | enhancement | model
    var message: String = ""            // one-line summary (list row)
    var logContent: String?             // full detail (shown on tap)
    var job: TranscriptionJob?          // optional link; nil = app-level event

    var level: LogLevel {
        get { LogLevel(rawValue: levelRaw) ?? .info }
        set { levelRaw = newValue.rawValue }
    }

    init(level: LogLevel, operationType: String, message: String,
         logContent: String? = nil, job: TranscriptionJob? = nil) {
        self.levelRaw = level.rawValue
        self.operationType = operationType
        self.message = message
        self.logContent = logContent
        self.job = job
    }
}

@Model
final class TranscriptionJob {
    var id: UUID = UUID()
    var sourcePath: String = ""
    var sourceFilename: String = ""
    var model: String = "openai_whisper-large-v3-v20240930_turbo"
    var language: String?            // nil = auto-detect
    var outputFormat: String = "txt"
    var outputPath: String?
    var transcriptText: String = ""      // full transcript, for enhancement / reuse
    var summaryPath: String?             // Claude enhancement output (.summary.md)
    var statusRaw: String = JobStatus.pending.rawValue
    var progress: Int = 0            // 0–100
    var durationAudio: Double?       // seconds
    var durationRun: Double?         // seconds
    var detectedLanguage: String?
    var errorMessage: String?

    // Advanced options (kept set, mirrors the trimmed Python backend).
    var task: String = "transcribe"
    var temperature: Double = 0.0    // 0 → engine uses fallback schedule
    var wordTimestamps: Bool = false
    var initialPrompt: String?
    var conditionOnPreviousText: Bool = true

    // §10.2 / §10.3 — pause & sleep checkpoint for resumable transcription.
    var lastCompletedChunk: Int = 0
    var partialTranscript: String = ""

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Logs attached to this job — deleted with it (mirrors the old FK CASCADE).
    @Relationship(deleteRule: .cascade, inverse: \ExecutionLog.job)
    var logs: [ExecutionLog] = []

    var status: JobStatus {
        get { JobStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(sourcePath: String, sourceFilename: String) {
        self.sourcePath = sourcePath
        self.sourceFilename = sourceFilename
    }
}

@Model
final class AppSettings {
    var defaultModel: String = "openai_whisper-large-v3-v20240930_turbo"
    var defaultLanguage: String = ""        // "" = auto
    var defaultOutputFormat: String = "txt"
    var defaultOutputDir: String = ""
    // Claude enhancement (port of the CLI-based integration).
    var claudeEnabled: Bool = false
    var claudeModel: String = "claude-opus-4-8"
    var claudeAutoAfterTranscribe: Bool = false
    /// Instruction prepended to the transcript when enhancing (editable in Settings).
    var claudePrompt: String = EnhancementService.defaultPrompt
    // Future §11.1 — Odoo Knowledge push.
    var odooBaseURL: String = ""

    init() {}
}
