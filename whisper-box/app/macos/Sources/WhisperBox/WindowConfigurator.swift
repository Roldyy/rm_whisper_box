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
        // Allow the green button (and ⌃⌘F) to take the window full-screen — without
        // .fullScreenPrimary macOS leaves the button as a no-op / plain zoom only.
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.standardWindowButton(.zoomButton)?.isEnabled = true   // green zoom / double-click title
    }
}

/// A title-bar-like hit area for the custom top bar. Under `.hiddenTitleBar` the SwiftUI
/// chrome covers the real title bar, so macOS's native double-click-to-zoom never fires.
/// This view restores it: double-click zooms ("full window"), a drag moves the window.
struct TitleBarDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        // Receive the mouseDown ourselves (true would hand it to the window for moving,
        // so clickCount could never reach 2); we re-initiate the drag manually below.
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return super.mouseDown(with: event) }
            if event.clickCount == 2 {
                window.performZoom(nil)
            } else {
                window.performDrag(with: event)
            }
        }
    }
}
