import ApplicationServices
import Cocoa
import os

/// Detects the currently focused UI element using macOS Accessibility APIs.
enum FocusedElementService {

    /// Resolve the currently focused text target.
    /// Must be called off the main thread to avoid hangs.
    static func currentTarget() -> FocusedTarget? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard err == .success, let focused = focusedValue else {
            Logger.insertion.debug("No focused element found")
            return nil
        }

        let element = focused as! AXUIElement

        // Read role
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = (roleValue as? String) ?? "unknown"

        // Check if kAXSelectedTextAttribute is settable (indicates editable element)
        var isSelectedTextSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &isSelectedTextSettable)

        // Check if kAXValueAttribute is settable (enables AX value splice strategy)
        var isValueAttrSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isValueAttrSettable)

        // Read selected text
        var selectedTextValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        let selectedText = selectedTextValue as? String

        // Read selection range
        var rangeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        var selectionRange: CFRange?
        if let rv = rangeValue {
            var range = CFRange(location: 0, length: 0)
            AXValueGetValue(rv as! AXValue, .cfRange, &range)
            selectionRange = range
        }

        // Get frontmost app info
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? "Unknown"
        let bundleID = frontApp?.bundleIdentifier

        let target = FocusedTarget(
            appName: appName,
            bundleIdentifier: bundleID,
            element: element,
            role: role,
            isEditable: isSelectedTextSettable.boolValue,
            hasSelection: selectionRange.map { $0.length > 0 } ?? false,
            selectionRange: selectionRange,
            selectedText: selectedText,
            isValueSettable: isValueAttrSettable.boolValue
        )

        Logger.insertion.info(
            "Focused target: app=\(appName) role=\(role) editable=\(target.isEditable) valueSettable=\(target.isValueSettable) hasSelection=\(target.hasSelection)"
        )

        return target
    }
}
