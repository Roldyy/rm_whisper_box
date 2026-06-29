import SwiftUI
import AppKit

/// Restores native window behaviors while keeping the custom dark chrome.
///
/// With `.windowStyle(.hiddenTitleBar)` the custom top bar covers the title-bar
/// region, so the window couldn't be dragged, double-clicked to zoom, or resized
/// the way users expect. This makes the whole window draggable by its background
/// and keeps the full-size-content title bar transparent/zoomable behind the chrome.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { Self.configure(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(nsView.window) }
    }

    private static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isMovableByWindowBackground = true       // drag the window from the custom top bar
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.resizable)             // edge resize
        window.standardWindowButton(.zoomButton)?.isEnabled = true   // green zoom / double-click title
    }
}
