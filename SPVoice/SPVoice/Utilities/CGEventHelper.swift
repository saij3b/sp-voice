import CoreGraphics
import Foundation
import os

/// Simulates keyboard events via CGEvent. Used for paste-fallback (Cmd+V).
enum CGEventHelper {

    /// Simulate pressing Cmd+V to paste from clipboard.
    ///
    /// - Parameters:
    ///   - tapLocation: Where to post the event.
    ///     `.cghidEventTap` is the default for native apps.
    ///     `.cgAnnotatedSessionEventTap` works better for Chromium browsers.
    ///   - keyPressDelay: Time between key-down and key-up in seconds.
    static func simulatePaste(
        tapLocation: CGEventTapLocation = .cghidEventTap,
        keyPressDelay: TimeInterval = 0.015
    ) {
        // Use a separate event source so our synthetic events don't interfere
        // with the real keyboard state. `.combinedSessionState` ensures the
        // target app sees the current modifier state correctly.
        let source = CGEventSource(stateID: .combinedSessionState)

        // First, post a flags-changed event with NO modifiers to clear any
        // residual modifier state the target app might think is held down
        // (common issue with Chromium when SP Voice's own hotkey uses Option).
        if let clearFlags = CGEvent(source: source) {
            clearFlags.type = .flagsChanged
            clearFlags.flags = []
            clearFlags.post(tap: tapLocation)
            Thread.sleep(forTimeInterval: 0.005)
        }

        // Virtual key code for 'V' is 0x09
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            Logger.insertion.error("Failed to create CGEvent for paste simulation")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: tapLocation)
        Thread.sleep(forTimeInterval: keyPressDelay)
        keyUp.post(tap: tapLocation)

        // Post a clean flags-changed to release Command, so the target app
        // doesn't think Command is still held.
        if let releaseFlags = CGEvent(source: source) {
            releaseFlags.type = .flagsChanged
            releaseFlags.flags = []
            releaseFlags.post(tap: tapLocation)
        }

        Logger.insertion.debug("Simulated Cmd+V paste event on tap=\(tapLocation.rawValue) keyDelay=\(keyPressDelay)s")
    }
}
