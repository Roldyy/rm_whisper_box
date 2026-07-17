import Foundation
import os
import SwiftData

/// Central log sink. Mirrors every event to `os.Logger` (Console.app / sysdiagnose)
/// and persists an `ExecutionLog` row for the in-app Logs tab + per-job view.
///
/// MainActor-isolated because SwiftData's main `ModelContext` is. Callers on other
/// threads/actors (the SCStream queue, the WhisperKit actor) reach it through the
/// nonisolated `Log.*` API, which hops here for the persisted row.
@MainActor
final class AppLog {
    static let shared = AppLog()

    /// Set once at startup (`RootView.onAppear`) — mirrors `TranscriptionManager.modelContext`.
    var modelContext: ModelContext?

    // Retention.
    let retentionDays = 14
    let maxLogCount = 2000

    private init() {}

    func persist(level: LogLevel, operation: String, message: String,
                 detail: String?, job: TranscriptionJob?) {
        guard let ctx = modelContext else { return }
        ctx.insert(ExecutionLog(level: level, operationType: operation,
                                message: message, logContent: detail, job: job))
        try? ctx.save()
    }

    /// Drop logs older than `retentionDays`, then cap to the newest `maxLogCount`.
    /// Called once on launch; per-job logs are pruned automatically by the cascade.
    func prune() {
        guard let ctx = modelContext else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())
            ?? .distantPast
        try? ctx.delete(model: ExecutionLog.self, where: #Predicate { $0.createdAt < cutoff })

        let desc = FetchDescriptor<ExecutionLog>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let all = try? ctx.fetch(desc), all.count > maxLogCount {
            for log in all[maxLogCount...] { ctx.delete(log) }
        }
        try? ctx.save()
    }

    func clearAll() {
        guard let ctx = modelContext else { return }
        try? ctx.delete(model: ExecutionLog.self)
        try? ctx.save()
    }
}

/// Ergonomic entry point: `Log.recording.error("…", detail: …)`,
/// `Log.transcription.success("Done", job: job)`.
enum Log {
    static let app = Category(operation: "app")
    static let recording = Category(operation: "recording")
    static let transcription = Category(operation: "transcription")
    static let enhancement = Category(operation: "enhancement")
    static let model = Category(operation: "model")

    struct Category {
        let operation: String
        private let logger: Logger

        init(operation: String) {
            self.operation = operation
            self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WhisperBox",
                                 category: operation)
        }

        func debug(_ m: String, job: TranscriptionJob? = nil, detail: String? = nil) { emit(.debug, m, detail, job) }
        func info(_ m: String, job: TranscriptionJob? = nil, detail: String? = nil) { emit(.info, m, detail, job) }
        func success(_ m: String, job: TranscriptionJob? = nil, detail: String? = nil) { emit(.success, m, detail, job) }
        func warning(_ m: String, job: TranscriptionJob? = nil, detail: String? = nil) { emit(.warning, m, detail, job) }
        func error(_ m: String, job: TranscriptionJob? = nil, detail: String? = nil) { emit(.error, m, detail, job) }

        private func emit(_ level: LogLevel, _ message: String, _ detail: String?, _ job: TranscriptionJob?) {
            // os.Logger — synchronous and thread-safe, so it runs on the calling thread.
            let line = detail.map { "\(message) — \($0)" } ?? message
            switch level {
            case .debug:            logger.debug("\(line, privacy: .public)")
            case .info, .success:   logger.info("\(line, privacy: .public)")
            case .warning:          logger.warning("\(line, privacy: .public)")
            case .error:            logger.error("\(line, privacy: .public)")
            }
            // Persisted row — hop to MainActor for SwiftData.
            let op = operation
            Task { @MainActor in
                AppLog.shared.persist(level: level, operation: op,
                                      message: message, detail: detail, job: job)
            }
        }
    }
}
