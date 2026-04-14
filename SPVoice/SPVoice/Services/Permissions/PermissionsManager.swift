import AVFoundation
import Cocoa
import Combine
import os
import ApplicationServices

@MainActor
final class PermissionsManager: ObservableObject {

    enum MicrophoneStatus: Equatable {
        case notDetermined
        case authorized
        case denied
    }

    @Published private(set) var accessibilityGranted: Bool = false
    @Published private(set) var inputMonitoringGranted: Bool = false
    @Published private(set) var microphoneStatus: MicrophoneStatus = .notDetermined

    private var pollTimer: Timer?
    private var statusRefreshTimer: Timer?
    private var activationObserver: Any?

    init() {
        refresh()
        startBackgroundStatusRefresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    // MARK: - Refresh

    func refresh() {
        let trusted = currentAccessibilityTrust()
        if trusted != accessibilityGranted {
            accessibilityGranted = trusted
        }

        let inputMonitoring = currentInputMonitoringTrust()
        if inputMonitoring != inputMonitoringGranted {
            inputMonitoringGranted = inputMonitoring
        }

        let mic = currentMicrophoneStatus()
        if mic != microphoneStatus {
            microphoneStatus = mic
        }
    }

    // MARK: - Accessibility

    /// Prompt the system accessibility dialog and begin polling for the grant.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
        startPollingAccessibility()
    }

    /// Open System Settings to the Accessibility pane.
    func openAccessibilitySettings() {
        if !accessibilityGranted {
            // Clear stale TCC entry (e.g. from a different signing identity) so macOS
            // will prompt for a fresh grant tied to the current binary's identity.
            resetTCC(for: "Accessibility")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refresh()
        startPollingAccessibility()
    }

    private func startPollingAccessibility() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let trusted = self.currentAccessibilityTrust()
                if trusted != self.accessibilityGranted {
                    self.accessibilityGranted = trusted
                    Logger.permissions.info("Accessibility permission changed: \(trusted)")
                }
                let inputMonitoring = self.currentInputMonitoringTrust()
                if inputMonitoring != self.inputMonitoringGranted {
                    self.inputMonitoringGranted = inputMonitoring
                    Logger.permissions.info("Input Monitoring permission changed: \(inputMonitoring)")
                }
                if trusted && inputMonitoring { self.pollTimer?.invalidate() }
            }
        }
    }

    private func startBackgroundStatusRefresh() {
        statusRefreshTimer?.invalidate()
        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    // MARK: - Microphone

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .authorized : .denied
        Logger.permissions.info("Microphone permission: \(granted ? "granted" : "denied")")
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        if !inputMonitoringGranted {
            // Clear stale TCC entry (e.g. from a different signing identity) so macOS
            // will prompt for a fresh grant tied to the current binary's identity.
            resetTCC(for: "ListenEvent")
            _ = CGRequestListenEventAccess()
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        refresh()
        startPollingAccessibility()
    }

    func requestInputMonitoring() {
        resetTCC(for: "ListenEvent")
        let granted = CGRequestListenEventAccess()
        inputMonitoringGranted = granted || currentInputMonitoringTrust()
        startPollingAccessibility()
    }

    // MARK: - TCC Reset

    private func resetTCC(for service: String) {
        let bundleID = Bundle.main.bundleIdentifier ?? SPVoiceConstants.bundleIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        try? process.run()
        process.waitUntilExit()
        Logger.permissions.info("TCC reset for \(service) (\(bundleID))")
    }

    private func currentMicrophoneStatus() -> MicrophoneStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    // MARK: - Aggregate

    var allPermissionsGranted: Bool {
        accessibilityGranted && inputMonitoringGranted && microphoneStatus == .authorized
    }

    private func currentAccessibilityTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            return true
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        return result == .success
    }

    private func currentInputMonitoringTrust() -> Bool {
        CGPreflightListenEventAccess()
    }

    deinit {
        pollTimer?.invalidate()
        statusRefreshTimer?.invalidate()
        if let observer = activationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
