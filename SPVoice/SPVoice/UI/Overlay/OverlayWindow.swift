import Cocoa
import SwiftUI

/// Borderless, always-on-top floating window for showing dictation state.
/// Phase 2: skeleton. Animation and positioning refined in Phase 5.
final class OverlayWindow: NSWindow {

    private let hostingController = NSHostingController(rootView: OverlayView(state: .idle, audioLevel: 0))

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 64),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        contentViewController = hostingController
    }

    /// Show the overlay at the bottom-center of the main screen.
    func showOverlay(state: DictationState, audioLevel: Float) {
        hostingController.rootView = OverlayView(state: state, audioLevel: audioLevel)

        // Position at bottom center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - frame.width / 2
            let y = screenFrame.minY + 80
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        orderFrontRegardless()
    }

    func hideOverlay() {
        orderOut(nil)
    }
}
