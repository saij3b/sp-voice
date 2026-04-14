import Cocoa
import SwiftUI

/// Borderless, always-on-top floating window for showing dictation state.
/// Uses NSPanel with .nonactivatingPanel so it NEVER steals focus from
/// the user's target app — critical for clipboard paste to land correctly.
final class OverlayWindow: NSPanel {

    // Extra padding around the pill so the SwiftUI shadow has room to render
    // without the window clipping it into a visible rectangle.
    private static let hPad: CGFloat = 60
    private static let vPad: CGFloat = 40
    private static let contentHeight: CGFloat = 52

    private let hostingController = NSHostingController(
        rootView: OverlayContainer(state: .idle, audioLevel: 0)
    )

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: Self.contentHeight + Self.vPad * 2),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // SwiftUI renders its own soft shadow; window shadow would clip to rect.
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        contentViewController = hostingController

        // Belt-and-suspenders: hosting view must have no background layer.
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = .clear
    }

    /// Show the overlay at the bottom-center of the main screen.
    func showOverlay(state: DictationState, audioLevel: Float) {
        hostingController.rootView = OverlayContainer(state: state, audioLevel: audioLevel)

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - frame.width / 2
            let y = screenFrame.minY + 80 - Self.vPad
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        orderFrontRegardless()
    }

    func hideOverlay() {
        orderOut(nil)
    }
}

/// Wraps OverlayView in a transparent, content-sized container so the
/// capsule hugs its content and the shadow has breathing room.
private struct OverlayContainer: View {
    let state: DictationState
    let audioLevel: Float

    var body: some View {
        OverlayView(state: state, audioLevel: audioLevel)
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
