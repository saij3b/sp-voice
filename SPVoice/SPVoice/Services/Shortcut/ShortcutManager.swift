import Cocoa
import Combine
import os

/// Manages global keyboard shortcut registration via CGEvent tap.
@MainActor
final class ShortcutManager: ObservableObject {

    struct KeyCombo: Equatable, Codable {
        var keyCode: UInt16
        var modifierFlags: UInt64 // Raw CGEventFlags value

        static let `default` = KeyCombo(
            keyCode: SPVoiceConstants.Defaults.defaultHotkeyKeyCode,
            modifierFlags: SPVoiceConstants.Defaults.defaultHotkeyModifierFlags.rawValue
        )

        var displayString: String {
            if Self.isModifierKey(keyCode) {
                return Self.keyCodeName(keyCode)
            }

            var parts: [String] = []
            let flags = CGEventFlags(rawValue: modifierFlags)
            if flags.contains(.maskControl) { parts.append("⌃") }
            if flags.contains(.maskAlternate) { parts.append("⌥") }
            if flags.contains(.maskShift) { parts.append("⇧") }
            if flags.contains(.maskCommand) { parts.append("⌘") }
            parts.append(Self.keyCodeName(keyCode))
            return parts.joined()
        }

        static func isModifierKey(_ code: UInt16) -> Bool {
            switch code {
            case 54, 55, 56, 58, 59, 60, 61, 62, 63:
                return true
            default:
                return false
            }
        }

        private static func keyCodeName(_ code: UInt16) -> String {
            switch code {
            case 54: return "R⌘"
            case 55: return "L⌘"
            case 56: return "L⇧"
            case 58: return "L⌥"
            case 59: return "L⌃"
            case 60: return "R⇧"
            case 61: return "R⌥"
            case 62: return "R⌃"
            case 63: return "Fn"
            case 0: return "A"
            case 1: return "S"
            case 2: return "D"
            case 3: return "F"
            case 4: return "H"
            case 5: return "G"
            case 6: return "Z"
            case 7: return "X"
            case 8: return "C"
            case 9: return "V"
            case 11: return "B"
            case 12: return "Q"
            case 13: return "W"
            case 14: return "E"
            case 15: return "R"
            case 16: return "Y"
            case 17: return "T"
            case 31: return "O"
            case 32: return "U"
            case 34: return "I"
            case 35: return "P"
            case 36: return "Return"
            case 37: return "L"
            case 38: return "J"
            case 40: return "K"
            case 45: return "N"
            case 46: return "M"
            case 48: return "Tab"
            case 49: return "Space"
            case 51: return "Delete"
            case 53: return "Esc"
            case 96: return "F5"
            case 97: return "F6"
            case 98: return "F7"
            case 99: return "F3"
            case 100: return "F8"
            case 101: return "F9"
            case 103: return "F11"
            case 105: return "F13"
            case 109: return "F10"
            case 111: return "F12"
            case 118: return "F4"
            case 120: return "F2"
            case 122: return "F1"
            case 123: return "←"
            case 124: return "→"
            case 125: return "↓"
            case 126: return "↑"
            default: return "Key(\(code))"
            }
        }
    }

    @Published var currentCombo: KeyCombo
    @Published var hotkeyMode: HotkeyMode
    @Published private(set) var isRegistered = false
    @Published private(set) var registrationError: String?

    /// Callbacks fired by the hotkey system.
    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?

    private var hotkeyTap: HotkeyTap?

    init() {
        let storedKeyCode = UserDefaults.standard.object(forKey: SPVoiceConstants.UserDefaultsKeys.globalHotkeyKeyCode) as? NSNumber
        let storedFlags = UserDefaults.standard.object(forKey: SPVoiceConstants.UserDefaultsKeys.globalHotkeyModifierFlags) as? NSNumber

        if let storedKeyCode, let storedFlags {
            currentCombo = KeyCombo(
                keyCode: storedKeyCode.uint16Value,
                modifierFlags: storedFlags.uint64Value
            )
        } else {
            currentCombo = .default
        }

        let mode = UserDefaults.standard.string(forKey: SPVoiceConstants.UserDefaultsKeys.hotkeyMode)
            .flatMap { HotkeyMode(rawValue: $0) }
        hotkeyMode = mode ?? .pushToTalk
    }

    // MARK: - Registration

    /// Register the global hotkey via CGEvent tap.
    /// Requires Input Monitoring permission. Accessibility enables the non-listen-only (intercepting) tap.
    func register() {
        unregister()

        let accessibilityTrusted = Self.currentAccessibilityTrust()
        let inputMonitoring = CGPreflightListenEventAccess()
        let isModifierOnly = KeyCombo.isModifierKey(currentCombo.keyCode)
        let preferListen = isModifierOnly || !accessibilityTrusted

        Logger.shortcut.info(
            "Registering hotkey: key=\(self.currentCombo.displayString) AX=\(accessibilityTrusted) InputMon=\(inputMonitoring) modifierOnly=\(isModifierOnly) preferListenOnly=\(preferListen)"
        )

        let tap = HotkeyTap(
            keyCode: currentCombo.keyCode,
            modifierMask: currentCombo.modifierFlags,
            preferListenOnly: preferListen
        )

        // Capture callbacks locally to avoid actor-isolation issues in the C callback
        let startCallback = onRecordingStart
        let stopCallback = onRecordingStop

        tap.onKeyDown = {
            DispatchQueue.main.async { startCallback?() }
        }
        tap.onKeyUp = {
            DispatchQueue.main.async { stopCallback?() }
        }

        if tap.install() {
            self.hotkeyTap = tap
            isRegistered = true
            registrationError = nil
            Logger.shortcut.info("Hotkey registered: \(self.currentCombo.displayString) listenOnly=\(tap.isListenOnly)")
        } else {
            isRegistered = false
            registrationError = "Event tap failed (AX=\(accessibilityTrusted), InputMon=\(inputMonitoring)). Grant Input Monitoring in System Settings, then click Re-register."
            Logger.shortcut.warning(
                "Cannot register hotkey — CGEvent.tapCreate returned nil. AX=\(accessibilityTrusted) InputMon=\(inputMonitoring)"
            )
        }
    }

    func unregister() {
        hotkeyTap?.uninstall()
        hotkeyTap = nil
        isRegistered = false
        Logger.shortcut.info("Hotkey unregistered")
    }

    // MARK: - Persistence

    func saveCombo(_ combo: KeyCombo) {
        var sanitizedCombo = combo
        // Modifier-only shortcuts are matched via flagsChanged by keyCode.
        if KeyCombo.isModifierKey(sanitizedCombo.keyCode) {
            sanitizedCombo.modifierFlags = 0
        }

        currentCombo = sanitizedCombo
        UserDefaults.standard.set(Int(sanitizedCombo.keyCode), forKey: SPVoiceConstants.UserDefaultsKeys.globalHotkeyKeyCode)
        UserDefaults.standard.set(sanitizedCombo.modifierFlags, forKey: SPVoiceConstants.UserDefaultsKeys.globalHotkeyModifierFlags)
        // Re-register with new combo
        unregister()
        register()
    }

    func saveMode(_ mode: HotkeyMode) {
        hotkeyMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: SPVoiceConstants.UserDefaultsKeys.hotkeyMode)
    }

    private static func currentAccessibilityTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: - CGEvent Tap Helper

/// Non-isolated helper that manages the raw CGEvent tap for global hotkey detection.
/// Must not be @MainActor — the C callback requires a non-isolated context.
final class HotkeyTap {

    let keyCode: UInt16
    let modifierMask: UInt64
    let preferListenOnly: Bool
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    private(set) var isListenOnly = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyDown = false

    init(keyCode: UInt16, modifierMask: UInt64, preferListenOnly: Bool = false) {
        self.keyCode = keyCode
        self.modifierMask = modifierMask
        self.preferListenOnly = preferListenOnly
    }

    func install() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let options: [CGEventTapOptions]
        if preferListenOnly {
            options = [.listenOnly]
        } else {
            options = [.defaultTap, .listenOnly]
        }

        let userInfoPtr = Unmanaged.passUnretained(self).toOpaque()
        var tap: CFMachPort?
        for tapOption in options {
            let optionName = tapOption == .listenOnly ? "listenOnly" : "defaultTap"
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: tapOption,
                eventsOfInterest: mask,
                callback: hotkeyTapCallback,
                userInfo: userInfoPtr
            )
            if tap != nil {
                isListenOnly = (tapOption == .listenOnly)
                Logger.shortcut.info("CGEvent.tapCreate succeeded with \(optionName)")
                break
            } else {
                Logger.shortcut.warning("CGEvent.tapCreate failed with \(optionName)")
            }
        }

        guard let tap else {
            Logger.shortcut.error("All CGEvent.tapCreate attempts failed — no event tap available")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    func uninstall() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isHotkeyDown = false
    }

    func reenable() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        let eventMods = flags.intersection(relevant).rawValue
        let targetMods = CGEventFlags(rawValue: modifierMask).intersection(relevant).rawValue

        if type == .flagsChanged,
           code == keyCode,
           let modifierFlag = Self.modifierFlag(for: code) {
            let isDown = flags.contains(modifierFlag)
            if isDown && !isHotkeyDown {
                isHotkeyDown = true
                onKeyDown?()
                return passThrough(event)
            }
            if !isDown && isHotkeyDown {
                isHotkeyDown = false
                onKeyUp?()
                return passThrough(event)
            }
        }

        if type == .keyDown {
            if code == keyCode && eventMods == targetMods && !isHotkeyDown {
                isHotkeyDown = true
                onKeyDown?()
                return passThrough(event)
            } else if code == keyCode && isHotkeyDown {
                return passThrough(event)
            }
        } else if type == .keyUp {
            if code == keyCode && isHotkeyDown {
                isHotkeyDown = false
                onKeyUp?()
                return passThrough(event)
            }
        }

        return Unmanaged.passUnretained(event) // pass through
    }

    private func passThrough(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if isListenOnly {
            return Unmanaged.passUnretained(event)
        }
        return nil
    }

    private static func modifierFlag(for keyCode: UInt16) -> CGEventFlags? {
        switch keyCode {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case 63: return .maskSecondaryFn
        default: return nil
        }
    }

    deinit {
        uninstall()
    }
}

// MARK: - C Callback

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }

    // Re-enable tap if system disabled it
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        let tap = Unmanaged<HotkeyTap>.fromOpaque(userInfo).takeUnretainedValue()
        tap.reenable()
        return Unmanaged.passUnretained(event)
    }

    let tap = Unmanaged<HotkeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handleEvent(type: type, event: event)
}
