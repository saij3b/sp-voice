import CoreGraphics
import os

/// Simulates keyboard events via CGEvent. Used for paste-fallback (Cmd+V).
/// Full implementation in Phase 4.
enum CGEventHelper {

    /// Simulate pressing Cmd+V to paste from clipboard.
    static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Virtual key code for 'V' is 0x09
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            Logger.insertion.error("Failed to create CGEvent for paste simulation")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        Logger.insertion.debug("Simulated Cmd+V paste event")
    }
}
