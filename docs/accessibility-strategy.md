# Accessibility & Text Insertion Strategy

## Overview

Text insertion is the most fragile part of SP Voice. The macOS Accessibility API (`AXUIElement`) is powerful but inconsistent across apps, especially Electron-based and browser-based text fields. This document details the insertion strategies, their trade-offs, and the fallback logic.

---

## Prerequisites

### App Configuration
- **App Sandbox must be DISABLED** — AXUIElement APIs silently fail in sandboxed apps.
- **Hardened Runtime** must be enabled (required for notarization), with the `com.apple.security.device.audio-input` exception.
- **Code signing** is required — unsigned apps cannot receive Accessibility trust.

### User Permissions
- The user must grant Accessibility permission in **System Settings → Privacy & Security → Accessibility**.
- Check: `AXIsProcessTrusted()` returns `true`.
- Prompt: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)`.
- After the user toggles the switch in System Settings, the app must be relaunched (or the permission is picked up dynamically — behavior varies by macOS version). Poll with a 1-second timer.

---

## Focused Element Detection

### Step-by-Step

```swift
// 1. Create system-wide accessibility object
let systemWide = AXUIElementCreateSystemWide()

// 2. Get the currently focused UI element
var focusedValue: CFTypeRef?
let focusError = AXUIElementCopyAttributeValue(
    systemWide,
    kAXFocusedUIElementAttribute as CFString,
    &focusedValue
)
guard focusError == .success, let focused = focusedValue else {
    // No focused element — can't insert
}
let focusedElement = focused as! AXUIElement

// 3. Get the role of the focused element
var roleValue: CFTypeRef?
AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &roleValue)
let role = roleValue as? String ?? "unknown"

// 4. Check if the element supports text insertion
let editableRoles: Set<String> = [
    kAXTextFieldRole,       // "AXTextField"
    kAXTextAreaRole,        // "AXTextArea"
    kAXComboBoxRole,        // "AXComboBox" — partial support
    kAXWebAreaRole,         // "AXWebArea" — contentEditable in browsers
]

// 5. Check if kAXSelectedTextAttribute is settable
var isSettable: DarwinBoolean = false
AXUIElementIsAttributeSettable(
    focusedElement,
    kAXSelectedTextAttribute as CFString,
    &isSettable
)

// 6. Get current selection range (for replacement logic)
var rangeValue: CFTypeRef?
AXUIElementCopyAttributeValue(
    focusedElement,
    kAXSelectedTextRangeAttribute as CFString,
    &rangeValue
)
```

### Important Threading Note
**AXUIElement calls must NOT be made on the main thread** in a tight loop — they can hang if the target app is unresponsive. Always dispatch to a background queue with a timeout.

---

## Insertion Strategies

### Strategy 1: Direct AX Selected-Text Insertion (Preferred)

**How it works**: Setting `kAXSelectedTextAttribute` replaces the current selection with the new text. If nothing is selected (cursor is a zero-width selection), the text is inserted at the cursor position.

```swift
let result = AXUIElementSetAttributeValue(
    focusedElement,
    kAXSelectedTextAttribute as CFString,
    text as CFTypeRef
)
// result == .success → inserted
```

**Works with**:
- NSTextField (native text fields)
- NSTextView (multi-line text areas: TextEdit, Notes, Xcode editor)
- Safari address bar
- Most native macOS controls

**Does NOT work with**:
- kAXComboBoxRole — `AXUIElementSetAttributeValue` returns `.success` but has no visible effect
- kAXWebAreaRole — varies by browser; Chrome and Firefox often ignore it for contentEditable
- Electron apps (Slack, VS Code, Discord) — partial or broken AX text support
- Terminal emulators — not standard text fields

**Failure mode**: Sometimes returns `.success` but the text doesn't actually appear. The app should verify insertion when possible by re-reading `kAXValueAttribute` after insertion and comparing.

### Strategy 2: AX Value Replacement

For elements where `kAXSelectedTextAttribute` doesn't work but `kAXValueAttribute` is readable and settable.

```swift
// 1. Read current value
var currentValueRef: CFTypeRef?
AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &currentValueRef)
let currentValue = (currentValueRef as? String) ?? ""

// 2. Read insertion point
var rangeRef: CFTypeRef?
AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef)

// 3. Compute new value
var range = CFRange(location: 0, length: 0)
if let axRange = rangeRef {
    AXValueGetValue(axRange as! AXValue, .cfRange, &range)
}

let startIndex = currentValue.index(currentValue.startIndex, offsetBy: range.location)
let endIndex = currentValue.index(startIndex, offsetBy: range.length)
var newValue = currentValue
newValue.replaceSubrange(startIndex..<endIndex, with: text)

// 4. Set updated value
AXUIElementSetAttributeValue(focusedElement, kAXValueAttribute as CFString, newValue as CFTypeRef)
```

**Works with**: Some combo boxes, search fields, and non-standard inputs.

**Caveat**: This replaces the entire value, which can cause the cursor to jump to the end and may trigger unexpected side effects (e.g., search fields firing a search on every value change).

### Strategy 3: Clipboard-Paste Fallback

The universal fallback when AX insertion fails.

```swift
// 1. Save current clipboard
let pasteboard = NSPasteboard.general
let savedContents = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
    guard let type = item.types.first,
          let data = item.data(forType: type) else { return nil }
    return (type.rawValue, data)
}

// 2. Set clipboard to new text
pasteboard.clearContents()
pasteboard.setString(text, forType: .string)

// 3. Simulate Cmd+V
let source = CGEventSource(stateID: .hidSystemState)
let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // 'V'
keyDown?.flags = .maskCommand
keyDown?.post(tap: .cghidEventTap)

let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
keyUp?.flags = .maskCommand
keyUp?.post(tap: .cghidEventTap)

// 4. Restore clipboard after delay
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
    pasteboard.clearContents()
    for (type, data) in savedContents ?? [] {
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
    }
}
```

**Works with**: Virtually everything that supports paste.

**Trade-offs**:
- Briefly clobbers the user's clipboard (restored after ~150ms)
- If the user pastes quickly after dictation, they might get stale clipboard content
- Cannot distinguish between "insert at cursor" and "replace selection" — depends on the target app's paste behavior
- Timing is sensitive: restore too early and the paste hasn't completed; too late and the user may have copied something else

---

## Fallback Decision Logic

```
func insert(text: String, into target: FocusedTarget) -> InsertionOutcome {
    // Check if this app requires clipboard-paste (known problematic apps)
    if shouldForceClipboardPaste(bundleID: target.bundleIdentifier) {
        return clipboardPaste(text)
    }

    // Strategy 1: Direct AX insertion
    if target.role ∈ {textField, textArea} && isSelectedTextSettable(target) {
        let result = directAXInsert(text, target)
        if result == .success {
            return .directAXSuccess
        }
    }

    // Strategy 2: AX value replacement
    if isValueSettable(target) {
        let result = axValueReplace(text, target)
        if result == .success {
            return .axValueReplaceSuccess
        }
    }

    // Strategy 3: Clipboard-paste fallback
    return clipboardPaste(text)
}
```

---

## Known Problematic Apps

These apps need special handling. This table is stored as a configurable dictionary (`[String: InsertionStrategy]`) so users can add their own overrides.

| App | Bundle ID | Issue | Recommended Strategy |
|---|---|---|---|
| Slack | `com.tinyspeck.slackmacgap` | AX insertion silently fails in message input | Clipboard-paste |
| VS Code | `com.microsoft.VSCode` | AX works in some fields, not in editor | Clipboard-paste |
| Discord | `com.hnc.Discord` | Electron: AX unreliable | Clipboard-paste |
| Terminal | `com.apple.Terminal` | Not a standard text field | Clipboard-paste |
| iTerm2 | `com.googlecode.iterm2` | Not a standard text field | Clipboard-paste |
| Chrome (web) | `com.google.Chrome` | contentEditable: AX partial | Clipboard-paste |
| Firefox (web) | `org.mozilla.firefox` | contentEditable: AX partial | Clipboard-paste |

Safari has better AX support than Chrome/Firefox for web text fields, so AX insertion is attempted first for Safari.

---

## Edge Cases

### Focus Changes During Transcription
- The user may switch apps while audio is being transcribed (1–3 seconds).
- `FocusedElementService` captures the target **after** transcription completes, not before recording starts.
- Risk: text inserts into the wrong app.
- Mitigation: optionally capture the focused app at recording start and compare with the focused app at insertion time. If they differ, show a warning and offer clipboard fallback.

### No Editable Element Focused
- User might have focus on a non-text element (e.g., a button, the desktop, Finder icon view).
- Detection: role is not in the editable set, or `isAttributeSettable` returns false.
- Fallback: copy text to clipboard and notify the user.

### Very Long Text Insertion
- Large transcripts (1000+ characters) may cause lag with AX insertion.
- Strategy 1 handles this fine for native controls.
- Strategy 3 (paste) is robust for any size.
- Consider chunking for Strategy 2 if the full-value replacement causes UI hangs.

### Rapid Sequential Dictations
- User dictates, then immediately dictates again.
- Must ensure the previous insertion is fully complete before starting a new cycle.
- Use a serial dispatch queue for insertion operations.

### Clipboard Restoration Race Condition
- If the user copies something to clipboard between our paste and our restore, we'll overwrite their new content.
- Mitigation: after the 150ms delay, check if the pasteboard change count has incremented since our write. If yes, someone else wrote to the clipboard — do not restore.

---

## Diagnostic Logging

Every insertion attempt logs:
- Target app name and bundle ID
- Focused element role
- Strategy attempted
- Strategy outcome (success / error code)
- Time taken for insertion
- Whether fallback was used

This data is surfaced in Settings → Diagnostics so users can report issues with specific apps.
