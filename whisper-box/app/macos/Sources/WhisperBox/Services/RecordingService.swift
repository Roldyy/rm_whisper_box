import Foundation
import Observation
import ScreenCaptureKit

enum RecordingState: String, Codable {
    case idle, recording, paused, stopped, endedBySleep   // §10.4
}

/// In-process recording orchestration (replaces the SCRecorder subprocess).
/// App-scoped so recording survives navigation; pause gates the writer; the
/// sleep hook finalizes a valid WAV instead of a truncated fragment (§10.3).
@MainActor
@Observable
final class RecordingService {
    private(set) var state: RecordingState = .idle
    /// #2 — true only during `start()`'s async setup (before the pipeline exists). Blocks
    /// a reentrant start without making stop()/pause()/quit think a recording is live.
    private(set) var isStarting = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastError: String?
    private(set) var outputURL: URL?

    /// Phase 5 — live transcript preview during recording.
    let live = LiveTranscriber()
    var liveEnabled = true

    private let power = PowerAssertion()   // §10.3 Layer 1 — prevent idle sleep

    /// Set by the app — used to route a finished recording to transcription.
    weak var transcriptionManager: TranscriptionManager?

    private var writer: WAVWriter?
    private var mixer: AudioMixer?
    private var systemCapturer: SystemAudioCapturer?
    private var micCapturer: MicCapturer?
    private var stream: SCStream?
    private var videoRecorder: VideoRecorder?   // #35 — optional screen/app video
    /// #35 — finalized video file for the current/last recording (nil if none).
    private(set) var videoURL: URL?
    private var liveContinuation: AsyncStream<[Float]>.Continuation?   // #28 — FIFO slice feed
    private var liveTask: Task<Void, Never>?
    private var timer: Timer?
    private var startedAt: Date?
    private var pausedAccum: TimeInterval = 0
    private var pauseStartedAt: Date?
    private var lastFlushElapsed: TimeInterval = 0   // #22 — last crash-safety header rewrite

    /// In-progress recordings are written here (always local); the finalized WAV
    /// is moved into `AppPaths.recordingsDir` on stop so a cloud-sync client never
    /// touches the open file. See #37.
    private static var stagingDir: URL { AppPaths.stagingDir }

    /// #32 — start using the persisted capture toggles, so ⌘R, the menu bar, and
    /// auto-start all honour what's chosen in the Record view / Settings.
    func startFromSettings() async throws {
        try await start(captureSystem: transcriptionManager?.captureSystem() ?? true,
                        captureMic: transcriptionManager?.captureMic() ?? true)
    }

    /// `captureSystem` uses ScreenCaptureKit (needs Screen Recording permission).
    /// With it off, only the mic is recorded → no screen-recording prompt.
    func start(captureSystem: Bool, captureMic: Bool) async throws {
        guard !isStarting, state == .idle || state == .stopped || state == .endedBySleep else { return }
        guard captureSystem || captureMic else {
            throw NSError(domain: "Recorder", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Select at least one audio source."])
        }
        lastError = nil
        // #2 — claim `isStarting` synchronously (before any await) so a second start()
        // is rejected, WITHOUT flipping state to .recording before the pipeline exists
        // (that made stop()/pause()/quit during setup act on a nil/stale pipeline).
        isStarting = true
        var committed = false
        defer { if !committed { isStarting = false; state = .idle } }

        let url = Self.stagingDir.appendingPathComponent("recording_\(Self.timestamp()).wav")
        let writer = WAVWriter(url: url)
        try writer.open()

        // Source indexing: system (if any) is 0, mic is next. Prepare mic before sizing.
        var mic: MicCapturer?
        if captureMic {
            let m = MicCapturer(sourceIndex: captureSystem ? 1 : 0)
            do { try m.prepare(); mic = m }
            catch { Log.recording.warning("Microphone preparation failed", detail: error.localizedDescription) }
        }
        let count = (captureSystem ? 1 : 0) + (mic != nil ? 1 : 0)
        guard count > 0 else {
            writer.finalize(); try? FileManager.default.removeItem(at: url)   // #10 — no orphan staging file
            throw NSError(domain: "Recorder", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone unavailable."])
        }
        let mixer = AudioMixer(writer: writer, sourceCount: count)
        mixer.onStall = { [weak self] source in            // #24
            let which = source == 0 && (self?.systemCapturer != nil) ? "system audio" : "microphone"
            Log.recording.warning("A capture source stalled and was dropped", detail: which)
            Task { @MainActor in self?.lastError = "\(which.capitalized) stopped delivering audio." }
        }
        if let m = mic {
            m.mixer = mixer
            do { try m.start() } catch {
                Log.recording.warning("Microphone start failed — recording without microphone",
                                      detail: error.localizedDescription)
                mixer.finish(source: m.sourceIndex); mic = nil
            }
        }

        if liveEnabled {
            live.start(language: transcriptionManager?.transcriptionLanguage())
            // #28 — feed slices through a FIFO AsyncStream so they reach the live
            // transcriber in delivery order (unstructured per-slice Tasks could race).
            let (slices, cont) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
            liveContinuation = cont
            mixer.onFlush = { slice in cont.yield(slice) }
            liveTask = Task { @MainActor [weak self] in
                for await slice in slices { self?.live.ingest(slice) }
            }
        }

        // SCStream drives system audio and/or video — both need Screen Recording.
        let videoMode = transcriptionManager?.videoCaptureMode() ?? "off"
        let wantsVideo = videoMode != "off"
        // #7 — one SCStream/filter can't scope video to a single app while still
        // capturing ALL system audio. When both are requested, keep the audio complete
        // (it's the transcription source) with a full-display filter; video is then
        // full-screen too for that recording.
        let effectiveVideoMode = (captureSystem && videoMode == "app") ? "screen" : videoMode
        if captureSystem && videoMode == "app" {
            Log.recording.warning("App-scoped video with system audio isn't supported together — recording full screen so system audio stays complete")
        }
        var systemCap: SystemAudioCapturer?
        var stream: SCStream?
        var video: VideoRecorder?
        self.videoURL = nil
        if captureSystem || wantsVideo {
          do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                throw NSError(domain: "Recorder", code: 10, userInfo: [NSLocalizedDescriptionKey: "No screen found"])
            }
            // Scope: a single chosen app (if running) or the whole display.
            let filter = Self.contentFilter(mode: effectiveVideoMode,
                                            appBundleID: transcriptionManager?.videoAppBundleID() ?? "",
                                            display: display, content: content)

            let config = SCStreamConfiguration()
            config.excludesCurrentProcessAudio = true      // #34 minor — don't capture our own output
            if captureSystem {
                config.capturesAudio = true
                config.sampleRate = 16000
                config.channelCount = 1
            }
            if wantsVideo {
                // #35 fix — pixels (not points) and even dimensions; H.264 rejects odd sizes.
                let (w, h) = Self.evenPixelSize(for: filter, fallback: display)
                config.width = w
                config.height = h
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)   // cap ~30 fps
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true
            }

            if captureSystem {
                let cap = SystemAudioCapturer(mixer: mixer, sourceIndex: 0)
                cap.onStop = { [weak self] err in
                    Log.recording.error("System audio stream interrupted", detail: err.localizedDescription)
                    Task { @MainActor in self?.lastError = err.localizedDescription }
                }
                systemCap = cap
            }
            if wantsVideo {
                let vurl = Self.stagingDir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".mp4")
                let vr = try VideoRecorder(url: vurl, width: config.width, height: config.height)
                vr.onStop = { [weak self] err in
                    Log.recording.error("Video stream interrupted", detail: err.localizedDescription)
                    Task { @MainActor in self?.lastError = err.localizedDescription }
                }
                video = vr
            }

            // SCStream needs one delegate; either output object works (both handle didStopWithError).
            let delegate: SCStreamDelegate = systemCap ?? video!
            let s = SCStream(filter: filter, configuration: config, delegate: delegate)
            if let cap = systemCap {
                try s.addStreamOutput(cap, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            }
            if let vr = video {
                try s.addStreamOutput(vr, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
            }
            try await s.startCapture()
            stream = s
          } catch {
            // #23 — the SCStream setup failed (Screen Recording denied, no display,
            // …). Unwind everything so no orphan/empty files or running engines leak.
            mic?.stop()
            if liveEnabled { liveContinuation?.finish(); liveTask?.cancel(); live.cancel() }
            writer.finalize()
            try? FileManager.default.removeItem(at: url)
            if let vurl = video?.url { try? FileManager.default.removeItem(at: vurl) }
            Log.recording.error("Recording failed to start", detail: error.localizedDescription)
            throw error
          }
        }

        self.writer = writer; self.mixer = mixer; self.systemCapturer = systemCap
        self.micCapturer = mic; self.stream = stream; self.videoRecorder = video; self.outputURL = url
        startedAt = Date(); pausedAccum = 0; pauseStartedAt = nil; lastFlushElapsed = 0
        state = .recording                                 // #2 — only now the pipeline exists
        isStarting = false
        committed = true                                   // setup succeeded; keep the state
        power.acquire(reason: "WhisperBox is recording")
        transcriptionManager?.prewarm()
        startTimer()
        Log.recording.success("Recording started",
                              detail: "system: \(captureSystem ? "yes" : "no") · mic: \(mic != nil ? "yes" : "no") · video: \(wantsVideo ? effectiveVideoMode : "no")")
    }

    /// #35 — capture only the chosen app's windows (when running) or the whole display.
    private static func contentFilter(mode: String, appBundleID: String,
                                      display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        if mode == "app", !appBundleID.isEmpty,
           let app = content.applications.first(where: { $0.bundleIdentifier == appBundleID }) {
            return SCContentFilter(display: display, including: [app], exceptingWindows: [])
        }
        if mode == "app" {
            Log.recording.warning("Video: chosen app isn't running — capturing the full screen instead")
        }
        return SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
    }

    /// #35 fix — the video's pixel size: `contentRect × pointPixelScale` gives the true
    /// captured pixel dimensions (incl. Retina) for either a display- or app-scoped
    /// filter; forced even because H.264 rejects odd width/height. Falls back to the
    /// display's point size if the filter reports nothing.
    private static func evenPixelSize(for filter: SCContentFilter, fallback display: SCDisplay) -> (Int, Int) {
        var w = display.width, h = display.height
        let rect = filter.contentRect
        if rect.width > 0, rect.height > 0 {
            let scale = CGFloat(filter.pointPixelScale)
            w = Int((rect.width * scale).rounded())
            h = Int((rect.height * scale).rounded())
        }
        if w % 2 != 0 { w -= 1 }
        if h % 2 != 0 { h -= 1 }
        return (max(2, w), max(2, h))
    }

    func pause() {
        guard state == .recording else { return }
        mixer?.isPaused = true
        videoRecorder?.setPaused(true)     // #4 — don't record the screen while paused
        pauseStartedAt = Date()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        if let p = pauseStartedAt { pausedAccum += Date().timeIntervalSince(p) }
        pauseStartedAt = nil
        mixer?.isPaused = false
        videoRecorder?.setPaused(false)    // #4
        mixer?.resetStallClocks()          // #24 fix — a long pause isn't a stall
        state = .recording
    }

    /// Stop, finalize the WAV, and return its URL (or nil if not recording).
    /// `finishLive: false` skips the live-tail transcription (used on sleep for speed).
    @discardableResult
    func stop(finishLive: Bool = true) async -> URL? {
        guard state == .recording || state == .paused else { return outputURL }
        state = .stopped                    // claim synchronously so a concurrent stop() no-ops
        timer?.invalidate(); timer = nil
        if let stream {
            do { try await stream.stopCapture() }
            catch { Log.recording.error("System capture stop failed", detail: error.localizedDescription) }
        }
        if systemCapturer != nil { mixer?.finish(source: 0) }   // system is source 0 when present
        micCapturer?.stop()                                     // removes tap, then finishes mic's source
        writer?.finalize()
        if let vr = videoRecorder {                             // #35 — finalize + adopt the video file
            await vr.finish()
            videoURL = moveStagedFileToOutput(vr.url)
        }
        moveStagedRecordingToOutput()                           // #37 — only the finalized file lands in the (maybe synced) output dir
        liveContinuation?.finish()                              // #28 — no more slices
        if finishLive && liveEnabled {
            await liveTask?.value                               // drain queued slices in order…
            await live.finish()                                // …then transcribe the tail
        }
        power.release()
        let url = outputURL
        state = .stopped
        cleanup()
        if let url { Log.recording.success("Recording saved", detail: url.lastPathComponent) }
        return url
    }

    /// Stop and route the result to transcription — live transcript as the
    /// deliverable, else a batch pass. Shared by the Record view and the menu bar.
    func stopAndTranscribe() async {
        guard let url = await stop() else { return }
        let text = live.transcript
        if liveEnabled, !text.isEmpty {
            transcriptionManager?.saveRecordingResult(filePath: url.path, transcript: text,
                                                      videoPath: videoURL?.path, duration: elapsed)
        } else {
            transcriptionManager?.start(filePath: url.path, videoPath: videoURL?.path)   // #8
        }
    }

    /// §10.3 Layer 2 — on system sleep, finalize a valid file rather than lose
    /// audio. Skips the live tail to finalize fast within the willSleep window.
    @discardableResult
    func handleSystemWillSleep() async -> URL? {
        guard state == .recording || state == .paused else { return nil }
        let elapsedAtSleep = elapsed
        let url = await stop(finishLive: false)     // stop() finalizes video and sets videoURL
        state = .endedBySleep
        if let url, !live.transcript.isEmpty {
            transcriptionManager?.saveRecordingResult(filePath: url.path, transcript: live.transcript,
                                                      videoPath: videoURL?.path, duration: elapsedAtSleep)
        }
        return url
    }

    /// #22 fix — on app Quit while recording: finalize the file fast (no live tail
    /// pass, which would delay termination and be discarded anyway) and persist a
    /// History job with whatever live transcript we have, so the recording isn't
    /// orphaned. Mirrors `handleSystemWillSleep`.
    func stopForTermination() async {
        guard state == .recording || state == .paused else { return }
        let elapsedAtQuit = elapsed
        let url = await stop(finishLive: false)
        if let url {
            if liveEnabled, !live.transcript.isEmpty {
                transcriptionManager?.saveRecordingResult(filePath: url.path, transcript: live.transcript,
                                                          videoPath: videoURL?.path, duration: elapsedAtQuit)
            } else {
                Log.recording.info("Recording finalized on quit", detail: url.lastPathComponent)
            }
        }
    }

    private func cleanup() {
        stream = nil; systemCapturer = nil; micCapturer = nil; mixer = nil; writer = nil
        videoRecorder = nil
        liveTask?.cancel(); liveTask = nil; liveContinuation = nil   // #28
    }

    /// #37 — move the finalized staging WAV into the configured output folder.
    private func moveStagedRecordingToOutput() {
        if let staged = outputURL { outputURL = moveStagedFileToOutput(staged) }
    }

    /// Move a finalized staging file into the configured output folder (which may be
    /// a OneDrive/iCloud sync root). Moving a *closed* file places a local copy
    /// immediately and lets the sync client upload in the background; on failure the
    /// file is left in staging rather than lost, and the returned URL points at
    /// wherever the file actually ended up. See #37.
    private func moveStagedFileToOutput(_ staged: URL) -> URL {
        guard FileManager.default.fileExists(atPath: staged.path) else { return staged }
        let dest = AppPaths.recordingDestination(for: staged.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: staged, to: dest)
            return dest
        } catch {
            Log.recording.warning("Couldn't move \(staged.lastPathComponent) into the output folder — kept in staging",
                                  detail: error.localizedDescription)
            return staged
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let s = startedAt else { return }
        let now = Date()
        let pausedNow = pausedAccum + (pauseStartedAt.map { now.timeIntervalSince($0) } ?? 0)
        elapsed = now.timeIntervalSince(s) - pausedNow
        // #22 crash resilience — refresh the WAV header at least every ~5 s (elapsed-
        // based so timer jitter can't skip a cycle) so a hard crash still leaves a
        // playable file. #24 — nudge the mixer's stall check.
        if state == .recording {
            if elapsed - lastFlushElapsed >= 5 { writer?.flushHeader(); lastFlushElapsed = elapsed }
            mixer?.checkStall()
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
