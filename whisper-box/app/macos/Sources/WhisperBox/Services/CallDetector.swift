import AppKit
import CoreAudio
import Foundation
import Observation

/// #36 — detects when a call likely starts, so the app can prompt (or auto-start)
/// a recording. There is no official "call started" event from Teams/Zoom/Meet, so
/// this is heuristic: a **Core Audio** listener on the default input device
/// (`kAudioDevicePropertyDeviceIsRunningSomewhere`) fires when *any* process begins
/// using the mic; on that rising edge, if a known conferencing app is running, we
/// bump `callStartToken`. Observers (RootView) decide whether to prompt or auto-start
/// based on the user's setting — this type only emits the signal.
///
/// No extra permission is required for the Core Audio property. Google Meet is
/// browser-based and can't be attributed reliably, so it isn't in the app list.
@MainActor
@Observable
final class CallDetector {
    /// Increments on each detected call start. Observe with `.onChange`.
    private(set) var callStartToken: Int = 0
    /// Name of the conferencing app seen at the last detection (for the prompt text).
    private(set) var lastDetectedApp: String?
    /// Whether that app was **frontmost** at detection. The mic edge can't be
    /// attributed to a PID, so a call app merely running in the background could be a
    /// false positive (another app grabbed the mic). Observers use this to be
    /// conservative — e.g. only silently auto-start when the call app is frontmost. (#3)
    private(set) var lastDetectionWasFrontmost = false

    /// Conferencing apps whose presence qualifies a mic-in-use edge as "a call".
    static let callAppBundleIDs: Set<String> = [
        "com.microsoft.teams",        // classic Teams
        "com.microsoft.teams2",       // new Teams
        "us.zoom.xos",                // Zoom
        "com.webex.meetingmanager",   // Webex (classic)
        "Cisco-Systems.Spark",        // Webex (newer)
        "com.tinyspeck.slackmacgap",  // Slack huddles
        "com.hnc.Discord",            // Discord
    ]

    /// #5 — set by the app so we ignore the mic-in-use edge WhisperBox itself causes
    /// (our own recording would otherwise look like a "call started").
    weak var recorder: RecordingService?

    private var listenedDevice: AudioObjectID?
    private var runningListener: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var lastRunning = false

    private var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    init() {
        attachDefaultDeviceListener()
        attachRunningListener(to: defaultInputDevice())
        lastRunning = isInputRunning(listenedDevice ?? 0)
    }

    // No deinit teardown: this is an app-lifetime object (a `@State` on the App),
    // and a @MainActor class's deinit is nonisolated so it can't touch the isolated
    // listener state anyway. The listeners are released when the process exits.

    // MARK: - Core Audio wiring

    private func attachRunningListener(to device: AudioObjectID) {
        // Detach any previous device first (default input can change at runtime).
        if let old = listenedDevice, let block = runningListener {
            AudioObjectRemovePropertyListenerBlock(old, &runningAddress, DispatchQueue.main, block)
            runningListener = nil; listenedDevice = nil
        }
        guard device != 0 else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.evaluate() }
        }
        let status = AudioObjectAddPropertyListenerBlock(device, &runningAddress, DispatchQueue.main, block)
        if status == noErr { runningListener = block; listenedDevice = device }
    }

    private func attachDefaultDeviceListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.attachRunningListener(to: self.defaultInputDevice())
                self.lastRunning = self.isInputRunning(self.listenedDevice ?? 0)
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, DispatchQueue.main, block)
        if status == noErr { defaultDeviceListener = block }
    }

    /// Rising edge (mic went unused → used) while a call app is running → emit.
    private func evaluate() {
        let running = isInputRunning(listenedDevice ?? 0)
        defer { lastRunning = running }
        guard running, !lastRunning else { return }
        // #5 — our own recording (incl. its async start) flips the mic-in-use flag;
        // don't treat that as a call.
        if let r = recorder, r.isStarting || r.state == .recording || r.state == .paused { return }
        guard let hit = detectedCallApp() else { return }
        lastDetectedApp = hit.name
        lastDetectionWasFrontmost = hit.frontmost
        callStartToken &+= 1
        Log.recording.info("Call detected",
                           detail: "\(hit.name) — mic in use\(hit.frontmost ? ", frontmost" : ", background")")
    }

    // MARK: - Queries

    private func defaultInputDevice() -> AudioObjectID {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, 0, nil, &size, &device)
        return device
    }

    private func isInputRunning(_ device: AudioObjectID) -> Bool {
        guard device != 0 else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    /// The conferencing app to attribute the mic edge to, preferring the frontmost
    /// one (a strong "user is in this call" signal) over a background one.
    private func detectedCallApp() -> (name: String, frontmost: Bool)? {
        if let front = NSWorkspace.shared.frontmostApplication,
           let id = front.bundleIdentifier, Self.callAppBundleIDs.contains(id) {
            return (front.localizedName ?? id, true)
        }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, Self.callAppBundleIDs.contains(id) {
                return (app.localizedName ?? id, false)
            }
        }
        return nil
    }
}
