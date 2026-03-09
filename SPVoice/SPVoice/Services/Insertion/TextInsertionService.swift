import ApplicationServices
import Foundation
import os

/// Inserts text into the currently focused element using a layered strategy chain:
/// 1. Direct AX insertion via `kAXSelectedTextAttribute`
/// 2. AX value splice via `kAXValueAttribute`
/// 3. Clipboard paste fallback via Cmd+V
enum TextInsertionService {

    /// Result of an insertion attempt, pairing the outcome with the detected target.
    struct InsertionResult {
        let outcome: InsertionOutcome
        let target: FocusedTarget?
    }

    /// Insert text into the current focused element, trying strategies in order.
    /// If `savedTarget` is provided (captured before transcription), it is preferred
    /// over re-detecting the focused element, which guards against focus changes.
    static func insert(_ text: String, savedTarget: FocusedTarget? = nil) async -> InsertionResult {
        Logger.insertion.info("Inserting text (\(text.count) chars)")

        // Use saved target if available, otherwise detect now.
        let target: FocusedTarget?
        if let savedTarget {
            target = savedTarget
            Logger.insertion.debug("Using saved insertion target: \(savedTarget.appName)")
        } else {
            target = await Task.detached {
                FocusedElementService.currentTarget()
            }.value
        }

        // Guard: focused element exists
        guard let target else {
            Logger.insertion.warning("No focused element — falling back to clipboard")
            return await clipboardFallback(text: text, target: nil)
        }

        // Guard: element is editable (try clipboard fallback for non-editable targets)
        guard target.isEditable else {
            Logger.insertion.warning(
                "Target not editable (app=\(target.appName) role=\(target.role)) — falling back to clipboard"
            )
            return await clipboardFallback(text: text, target: target)
        }

        // Strategy 1: Direct AX insertion via kAXSelectedTextAttribute
        if let result = tryDirectAXInsertion(text: text, target: target) {
            return result
        }

        // Strategy 2: AX value splice via kAXValueAttribute
        if let result = tryAXValueSplice(text: text, target: target) {
            return result
        }

        // Strategy 3: Clipboard paste fallback
        Logger.insertion.info("AX strategies exhausted — using clipboard paste fallback")
        return await clipboardFallback(text: text, target: target)
    }

    // MARK: - Strategy 1: Direct AX Insertion

    /// Set `kAXSelectedTextAttribute` to replace the current selection (or insert at cursor).
    /// This is the cleanest method — preserves undo stack in most Cocoa apps.
    private static func tryDirectAXInsertion(text: String, target: FocusedTarget) -> InsertionResult? {
        let result = AXUIElementSetAttributeValue(
            target.element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        if result == .success {
            Logger.insertion.info(
                "Direct AX insertion succeeded (app=\(target.appName) role=\(target.role))"
            )
            return InsertionResult(outcome: .directAXSuccess, target: target)
        }

        Logger.insertion.debug(
            "Direct AX insertion failed: \(result.rawValue) (app=\(target.appName))"
        )
        return nil
    }

    // MARK: - Strategy 2: AX Value Splice

    /// Read the full `kAXValueAttribute`, splice the new text in at the cursor/selection, and write back.
    /// Works when direct selected-text insertion fails but the full value is accessible.
    private static func tryAXValueSplice(text: String, target: FocusedTarget) -> InsertionResult? {
        guard target.isValueSettable else {
            Logger.insertion.debug("AX value not settable — skipping splice strategy")
            return nil
        }

        // Read current value
        var currentValueRef: CFTypeRef?
        let readResult = AXUIElementCopyAttributeValue(
            target.element,
            kAXValueAttribute as CFString,
            &currentValueRef
        )
        guard readResult == .success, let currentValue = currentValueRef as? String else {
            Logger.insertion.debug("Failed to read AX value: \(readResult.rawValue)")
            return nil
        }

        // Determine insertion point from selection range
        let insertionRange: Range<String.Index>
        if let cfRange = target.selectionRange,
           cfRange.location != kCFNotFound,
           cfRange.location >= 0,
           cfRange.location + cfRange.length <= currentValue.count
        {
            let start = currentValue.index(currentValue.startIndex, offsetBy: cfRange.location)
            let end = currentValue.index(start, offsetBy: cfRange.length)
            insertionRange = start ..< end
        } else {
            // No valid range — append at end
            insertionRange = currentValue.endIndex ..< currentValue.endIndex
        }

        // Splice new text
        var newValue = currentValue
        newValue.replaceSubrange(insertionRange, with: text)

        // Write back
        let writeResult = AXUIElementSetAttributeValue(
            target.element,
            kAXValueAttribute as CFString,
            newValue as CFTypeRef
        )

        if writeResult == .success {
            // Move cursor to end of inserted text
            let newCursorLocation = currentValue.distance(
                from: currentValue.startIndex,
                to: insertionRange.lowerBound
            ) + text.count
            setCursorPosition(element: target.element, location: newCursorLocation)

            Logger.insertion.info(
                "AX value splice succeeded (app=\(target.appName) role=\(target.role))"
            )
            return InsertionResult(outcome: .axValueReplaceSuccess, target: target)
        }

        Logger.insertion.debug(
            "AX value splice write failed: \(writeResult.rawValue) (app=\(target.appName))"
        )
        return nil
    }

    /// Move the cursor to a specific position after a value splice.
    private static func setCursorPosition(element: AXUIElement, location: Int) {
        var range = CFRange(location: location, length: 0)
        guard let axValue = AXValueCreate(.cfRange, &range) else { return }
        AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axValue
        )
    }

    // MARK: - Strategy 3: Clipboard Paste Fallback

    /// Save clipboard → set text → simulate Cmd+V → restore clipboard.
    /// Universal fallback that works in virtually all apps.
    private static func clipboardFallback(text: String, target: FocusedTarget?) async -> InsertionResult {
        let saved = PasteboardHelper.saveClipboard()
        PasteboardHelper.setClipboardText(text)

        CGEventHelper.simulatePaste()

        // Wait for the paste event to be processed by the target app
        try? await Task.sleep(for: .seconds(SPVoiceConstants.Defaults.clipboardRestoreDelay))

        PasteboardHelper.restoreClipboard(saved)

        Logger.insertion.info(
            "Clipboard paste fallback used (app=\(target?.appName ?? "unknown") role=\(target?.role ?? "unknown"))"
        )
        return InsertionResult(outcome: .clipboardPasteSuccess, target: target)
    }
}
