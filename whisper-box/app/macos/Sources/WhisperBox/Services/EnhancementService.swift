import Foundation

/// Claude enhancement — port of `claude_runner.py`. Runs the `claude` CLI via
/// Process, injecting the OAuth token from Keychain and stripping
/// ANTHROPIC_API_KEY so usage bills against the subscription, not per-token.
struct EnhancementService {
    /// Default instruction prepended to the transcript (editable in Settings).
    static let defaultPrompt = """
    Tu es un assistant qui résume des transcriptions audio.
    Produis un résumé concis (5-10 points clés) de la transcription ci-dessous.
    Réponds dans la langue de la transcription.
    """

    /// Neutral app-owned working dir for the `claude` subprocess (avoids it
    /// scanning protected user folders → spurious TCC prompts).
    private static func workingDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("WhisperBox/claude-work", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let candidatePaths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                                         "\(NSHomeDirectory())/.npm-global/bin/claude"]

    /// Locate the `claude` binary across common install dirs (Homebrew, npm).
    private static func claudeBinary() -> String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Whether the `claude` CLI is installed (for the Settings indicator + a clear error).
    static var isAvailable: Bool { claudeBinary() != nil }

    /// Run `claude -p` with `prompt` followed by the transcript. Returns stdout.
    func enhance(_ text: String, prompt: String, model: String) async throws -> String {
        guard let bin = Self.claudeBinary() else {
            throw NSError(domain: "Enhancement", code: 127, userInfo: [NSLocalizedDescriptionKey:
                "CLI « claude » introuvable — installez @anthropic-ai/claude-code et connectez-vous."])
        }
        let fullPrompt = prompt + "\n\nTranscription :\n" + text

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["-p", "--model", model]

        // Run `claude` in a neutral, app-owned directory. Otherwise it inspects
        // its inherited CWD (often the home folder) and enumerating that triggers
        // Documents/Desktop/Downloads TCC prompts attributed to WhisperBox.
        proc.currentDirectoryURL = Self.workingDirectory()

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ANTHROPIC_API_KEY")          // force subscription billing
        if let token = KeychainService.get() { env["CLAUDE_CODE_OAUTH_TOKEN"] = token }
        proc.environment = env

        let stdin = Pipe(), stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        try proc.run()
        stdin.fileHandleForWriting.write(Data(fullPrompt.utf8))
        stdin.fileHandleForWriting.closeFile()

        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "Enhancement", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "claude CLI a échoué (code \(proc.terminationStatus))"])
        }
        return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
