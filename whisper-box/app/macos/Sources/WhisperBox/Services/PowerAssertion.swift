import Foundation
import IOKit.pwr_mgt

/// Prevents *idle* system sleep while recording/transcribing (§10.3 Layer 1).
/// Note: cannot block forced or lid-close sleep — the willSleep handler (Layer 2)
/// covers those.
final class PowerAssertion {
    private var id: IOPMAssertionID = IOPMAssertionID(0)
    private var active = false

    func acquire(reason: String) {
        guard !active else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        active = (result == kIOReturnSuccess)
    }

    func release() {
        guard active else { return }
        IOPMAssertionRelease(id)
        active = false
    }

    deinit { release() }
}
