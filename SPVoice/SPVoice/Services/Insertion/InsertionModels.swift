import ApplicationServices
import Foundation

/// Normalized representation of the currently focused text target.
struct FocusedTarget {
    let appName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let element: AXUIElement
    let role: String
    let subRole: String?
    let isEditable: Bool
    /// Whether the target app is a known Chromium-based browser.
    let isChromium: Bool
    let hasSelection: Bool
    let selectionRange: CFRange?
    let selectedText: String?
    /// Whether `kAXValueAttribute` can be written (enables AX value splice strategy).
    let isValueSettable: Bool
}

/// Outcome of a text insertion attempt.
enum InsertionOutcome: Equatable {
    case directAXSuccess
    case axValueReplaceSuccess
    case clipboardPasteSuccess
    case clipboardCopied
    case failed(InsertionError)
}

/// Detailed insertion failure reasons.
enum InsertionError: Error, LocalizedError, Equatable {
    case accessibilityNotTrusted
    case noFocusedElement
    case elementNotEditable
    case axInsertionFailed(String)
    case clipboardPasteFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotTrusted: return "Accessibility permission required"
        case .noFocusedElement: return "No text field detected"
        case .elementNotEditable: return "Target is not editable"
        case .axInsertionFailed(let msg): return "AX insertion failed: \(msg)"
        case .clipboardPasteFailed: return "Clipboard paste failed"
        }
    }
}
