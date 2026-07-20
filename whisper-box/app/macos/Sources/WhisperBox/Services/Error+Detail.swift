import Foundation

extension Error {
    /// Full diagnostic string for logs: message + domain/code, unwrapping nested
    /// `NSUnderlyingError`s. `localizedDescription` alone collapses many failures
    /// (TCC denials, Core Audio errors) to a useless "operation couldn't be completed".
    var fullDescription: String {
        let ns = self as NSError
        var line = "\(ns.localizedDescription) [\(ns.domain) \(ns.code)]"
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            line += " ← \(underlying.fullDescription)"
        }
        return line
    }

    /// True if this (or an underlying) error is a file-permission / TCC denial —
    /// the user's own file exists and is POSIX-readable, but macOS blocks the open.
    var isFilePermissionError: Bool {
        let ns = self as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError { return true }
        if ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EPERM) || ns.code == Int(EACCES)) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return underlying.isFilePermissionError }
        return false
    }
}
