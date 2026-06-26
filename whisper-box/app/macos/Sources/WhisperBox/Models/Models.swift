import Foundation
import SwiftData

// SwiftData models. Greenfield (no import from the old app.db, per decision).
// Includes the pause/sleep additions from SWIFT_MIGRATION_PLAN.md §10.4.

enum JobStatus: String, Codable {
    case pending, running, paused, success, error, cancelled
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
final class ExecutionLog {
    var id: UUID = UUID()
    var jobID: UUID?
    var operationType: String = ""
    var status: String = ""
    var logContent: String = ""
    var createdAt: Date = Date()

    init(operationType: String, status: String, logContent: String = "") {
        self.operationType = operationType
        self.status = status
        self.logContent = logContent
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
