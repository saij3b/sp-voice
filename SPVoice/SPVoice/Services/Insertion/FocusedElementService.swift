import ApplicationServices
import Cocoa
import os

/// Detects the currently focused UI element using macOS Accessibility APIs.
enum FocusedElementService {

    /// Known Chromium-based browser bundle IDs.
    static let chromiumBundleIDs: Set<String> = [
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.google.Chrome.beta",
        "company.thebrowser.Browser",     // Arc
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
    ]

    /// Resolve the currently focused text target.
    /// Must be called off the main thread to avoid hangs.
    static func currentTarget() -> FocusedTarget? {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? "Unknown"
        let bundleID = frontApp?.bundleIdentifier
        let isChromium = bundleID.map { chromiumBundleIDs.contains($0) } ?? false

        guard let element = resolveFocusedElement(frontApp: frontApp) else {
            Logger.insertion.debug("No focused element found for app=\(appName)")
            return nil
        }

        // Read role
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = (roleValue as? String) ?? "unknown"

        // Read subrole (useful for Chromium contenteditable detection)
        var subRoleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subRoleValue)
        let subRole = subRoleValue as? String

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

        // Chromium web views need relaxed editability detection:
        // the focused element may be AXWebArea, AXGroup, AXTextField, or AXTextArea
        // but AX attribute checks can return false even when the field IS editable.
        let isEditable: Bool
        if isChromium {
            isEditable = isSelectedTextSettable.boolValue
                || isValueAttrSettable.boolValue
                || editableRoles.contains(role)
                || chromiumEditableRoles.contains(role)
                || subRole == "AXContentEditable"
        } else {
            isEditable = isSelectedTextSettable.boolValue
                || isValueAttrSettable.boolValue
                || editableRoles.contains(role)
        }

        let target = FocusedTarget(
            appName: appName,
            bundleIdentifier: bundleID,
            processIdentifier: processIdentifier(for: element, fallback: frontApp?.processIdentifier ?? 0),
            element: element,
            role: role,
            subRole: subRole,
            isEditable: isEditable,
            isChromium: isChromium,
            hasSelection: selectionRange.map { $0.length > 0 } ?? false,
            selectionRange: selectionRange,
            selectedText: selectedText,
            isValueSettable: isValueAttrSettable.boolValue
        )

        Logger.insertion.info(
            "Focused target: app=\(appName) bundle=\(bundleID ?? "nil") role=\(role) subRole=\(subRole ?? "nil") editable=\(target.isEditable) chromium=\(isChromium) valueSettable=\(target.isValueSettable)"
        )

        return target
    }

    /// Re-probe the focused element for a specific app PID.
    /// Lighter weight than `currentTarget()` — used right before paste
    /// to verify focus is still in a viable target.
    static func reprobeTarget(pid: pid_t) -> FocusedTarget? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let element = focusedElement(from: appElement) else { return nil }

        let runningApp = NSRunningApplication(processIdentifier: pid)
        let appName = runningApp?.localizedName ?? "PID:\(pid)"
        let bundleID = runningApp?.bundleIdentifier
        let isChromium = bundleID.map { chromiumBundleIDs.contains($0) } ?? false

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = (roleValue as? String) ?? "unknown"

        var subRoleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subRoleValue)
        let subRole = subRoleValue as? String

        return FocusedTarget(
            appName: appName,
            bundleIdentifier: bundleID,
            processIdentifier: pid,
            element: element,
            role: role,
            subRole: subRole,
            isEditable: true,       // Assume editable for reprobe — we're pasting anyway
            isChromium: isChromium,
            hasSelection: false,
            selectionRange: nil,
            selectedText: nil,
            isValueSettable: false
        )
    }

    private static let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        "AXSearchField",
        kAXComboBoxRole as String
    ]

    /// Chromium-specific roles that indicate an editable web element.
    private static let chromiumEditableRoles: Set<String> = [
        "AXWebArea",
        "AXGroup",
        "AXGenericElement"
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
