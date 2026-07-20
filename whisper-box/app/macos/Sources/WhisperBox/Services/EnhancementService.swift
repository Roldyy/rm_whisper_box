import Foundation

/// Claude enhancement — port of `claude_runner.py`. Runs the `claude` CLI via
/// Process, injecting the OAuth token from Keychain and stripping
/// ANTHROPIC_API_KEY so usage bills against the subscription, not per-token.
struct EnhancementService {
    /// Default instruction prepended to the transcript (editable in Settings).
    static let defaultPrompt = """
    Tu es un assistant expert en synthèse de réunions. Ton rôle est de résumer la transcription audio ci-dessous de manière claire, structurée et directement exploitable.

    Instructions de structure :

    1. Bandeau d'avertissement : Commence impérativement ton message par le bloc exact suivant (au format Markdown) :

    > ⚠️ **CONTENU GÉNÉRÉ PAR IA – À RELIRE ET VÉRIFIER**
    > *Ce résumé a été produit automatiquement à partir d'une transcription. Veuillez valider les points clés et les actions avant toute diffusion.*
    ---

    2. Synthèse globale : Juste après le bandeau, décris en une seule phrase l'objectif principal ou le sujet de la discussion.

    3. Points clés (5 à 10 puces) : Rédige des points percutants qui mettent en avant les décisions prises, les insights majeurs et les prochaines étapes (qui fait quoi, pour quand).

    Règles de style et de forme :

    - Ignore les répétitions, les tics de langage et les phrases inachevées du transcript. Reste professionnel, factuel et concis.
    - Réponds strictement dans la langue de la transcription.
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
                                         "\(NSHomeDirectory())/.npm-global/bin/claude",
                                         "\(NSHomeDirectory())/.local/bin/claude",       // #31 native installer
                                         "\(NSHomeDirectory())/.claude/local/claude"]     // #31 local install

    /// Locate the `claude` binary across common install dirs (Homebrew, npm).
    private static func claudeBinary() -> String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Whether the `claude` CLI is installed (for the Settings indicator + a clear error).
    static var isAvailable: Bool { claudeBinary() != nil }

    /// Max wall-clock for a single `claude` run before we give up and kill it.
    static let timeout: TimeInterval = 180

    /// Run `claude -p` with `prompt` followed by the transcript. Returns stdout.
    /// #26 — stdout/stderr are drained on detached tasks (concurrently, so a large
    /// response can't deadlock the pipe), completion is polled without parking a
    /// cooperative thread in `waitUntilExit`, stderr is surfaced in the error, and a
    /// timeout kills a hung process.
    func enhance(_ text: String, prompt: String, model: String) async throws -> String {
        guard let bin = Self.claudeBinary() else {
            throw NSError(domain: "Enhancement", code: 127, userInfo: [NSLocalizedDescriptionKey:
                "claude CLI not found — install @anthropic-ai/claude-code and sign in."])
        }
        let fullPrompt = prompt + "\n\nTranscription:\n" + text

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

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr
        try proc.run()

        // Feed the prompt, then close stdin so `claude` starts working. #6 — the
        // throwing write surfaces a broken pipe (claude exited early) as a catchable
        // error rather than SIGPIPE; the non-zero exit below reports the real cause.
        do { try stdin.fileHandleForWriting.write(contentsOf: Data(fullPrompt.utf8)) }
        catch { Log.enhancement.warning("Couldn't send prompt to claude", detail: error.localizedDescription) }
        try? stdin.fileHandleForWriting.close()

        // Drain both pipes concurrently on detached tasks (won't block the caller's
        // cooperative thread, and prevents a full-pipe deadlock on large output).
        async let outData = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }.value
        async let errData = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }.value

        // Poll for exit with a timeout instead of parking a thread in waitUntilExit.
        let deadline = Date().addingTimeInterval(Self.timeout)
        while proc.isRunning {
            if Date() >= deadline {
                proc.terminate()
                throw NSError(domain: "Enhancement", code: 124, userInfo: [NSLocalizedDescriptionKey:
                    "claude timed out after \(Int(Self.timeout))s."])
            }
            do {
                try await Task.sleep(nanoseconds: 100_000_000)   // 100 ms
            } catch {
                // Cancelled — kill the child and propagate (don't busy-spin on `try?`).
                proc.terminate()
                throw CancellationError()
            }
        }

        let out = String(decoding: await outData, as: UTF8.self)
        let err = String(decoding: await errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard proc.terminationStatus == 0 else {
            let detail = err.isEmpty ? "code \(proc.terminationStatus)" : err
            throw NSError(domain: "Enhancement", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "claude CLI failed: \(detail)"])
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
