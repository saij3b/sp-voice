import CoreGraphics
import Foundation

enum SPVoiceConstants {
    static let bundleIdentifier = "com.spvoice.app"
    static let keychainService = "com.spvoice.credentials"
    static let logSubsystem = "com.spvoice"

    enum Defaults {
        static let maxHistoryEntries = 100
        static let defaultHotkeyKeyCode: UInt16 = 49 // Space
        static let defaultHotkeyModifierFlags: CGEventFlags = .maskAlternate // Option
        static let transcriptionTimeoutSeconds: TimeInterval = 15
        static let minRecordingDuration: TimeInterval = 0.3
        static let maxRecordingDuration: TimeInterval = 300 // 5 minutes
        static let audioSampleRate: Double = 16_000
        static let clipboardRestoreDelay: TimeInterval = 0.3
    }

    enum UserDefaultsKeys {
        static let selectedPrimaryProvider = "selectedPrimaryProvider"
        static let selectedSecondaryProvider = "selectedSecondaryProvider"
        static let providerFallbackOrder = "providerFallbackOrder"
        static let modelPerProvider = "modelPerProvider"
        static let globalHotkeyKeyCode = "globalHotkeyKeyCode"
        static let globalHotkeyModifierFlags = "globalHotkeyModifierFlags"
        static let hotkeyMode = "hotkeyMode"
        static let textProcessingMode = "textProcessingMode"
        static let autoInsertEnabled = "autoInsertEnabled"
        static let historyEnabled = "historyEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }
}
