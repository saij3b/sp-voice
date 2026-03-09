import ApplicationServices
import Cocoa
import os

/// Detects the currently focused UI element using macOS Accessibility APIs.
enum FocusedElementService {

    /// Resolve the currently focused text target.
    /// Must be called off the main thread to avoid hangs.
    static func currentTarget() -> FocusedTarget? {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? "Unknown"
        let bundleID = frontApp?.bundleIdentifier

        guard let element = resolveFocusedElement(frontApp: frontApp) else {
            Logger.insertion.debug("No focused element found for app=\(appName)")
            return nil
        }

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

        let isEditable = isSelectedTextSettable.boolValue
            || isValueAttrSettable.boolValue
            || editableRoles.contains(role)

        let target = FocusedTarget(
            appName: appName,
            bundleIdentifier: bundleID,
            processIdentifier: processIdentifier(for: element, fallback: frontApp?.processIdentifier ?? 0),
            element: element,
            role: role,
            isEditable: isEditable,
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

    private static let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        "AXSearchField",
        kAXComboBoxRole as String
    ]

    private static func resolveFocusedElement(frontApp: NSRunningApplication?) -> AXUIElement? {
        if let pid = frontApp?.processIdentifier,
           let element = focusedElement(from: AXUIElementCreateApplication(pid)) {
            return element
        }

        let systemWide = AXUIElementCreateSystemWide()
        if let element = focusedElement(from: systemWide) {
            return element
        }

        return nil
    }

    private static func focusedElement(from root: AXUIElement) -> AXUIElement? {
        if let value = attributeValue(kAXFocusedUIElementAttribute as CFString, on: root) {
            return value as! AXUIElement
        }

        guard let windowValue = attributeValue(kAXFocusedWindowAttribute as CFString, on: root) else {
            return nil
        }
        let window = windowValue as! AXUIElement

        guard let value = attributeValue(kAXFocusedUIElementAttribute as CFString, on: window) else {
            return nil
        }
        return value as! AXUIElement
    }

    private static func attributeValue(_ attribute: CFString, on element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value
    }

    private static func processIdentifier(for element: AXUIElement, fallback: pid_t) -> pid_t {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        if result == .success, pid > 0 {
            return pid
        }
        return fallback
    }
}
