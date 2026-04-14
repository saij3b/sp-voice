import AppKit
import Combine
import Foundation
import os

/// Central coordinator that owns all service instances and orchestrates the dictation lifecycle.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Services

    let permissionsManager: PermissionsManager
    let credentialsStore: CredentialsStore
    let providerManager: ProviderManager
    let shortcutManager: ShortcutManager
    let audioRecorder: AudioRecorder
    let transcriptionService: TranscriptionService
    let historyStore: HistoryStore
    let diagnosticsService: DiagnosticsService

    // MARK: - State

    @Published var dictationState: DictationState = .idle
    @Published var hasCompletedOnboarding: Bool
    @Published var showOnboarding: Bool = false
    @Published var showSettings: Bool = false
    @Published var lastTranscription: String?
    @Published var lastError: String?

    /// Saved insertion target captured when recording starts, used to survive focus changes.
    private var savedInsertionTarget: FocusedTarget?
    private var savedInsertionAppPID: pid_t?
    private var transcriptionTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let overlayWindow = OverlayWindow()

    // MARK: - Init

    init() {
        let permissions = PermissionsManager()
        let credentials = CredentialsStore()
        let providers = ProviderManager(credentialsStore: credentials)
        let shortcuts = ShortcutManager()
        let recorder = AudioRecorder()
        let transcription = TranscriptionService(providerManager: providers)
        let history = HistoryStore()
        let diagnostics = DiagnosticsService()

        self.permissionsManager = permissions
        self.credentialsStore = credentials
        self.providerManager = providers
        self.shortcutManager = shortcuts
        self.audioRecorder = recorder
        self.transcriptionService = transcription
        self.historyStore = history
        self.diagnosticsService = diagnostics

        self.hasCompletedOnboarding = UserDefaults.standard.bool(
            forKey: SPVoiceConstants.UserDefaultsKeys.hasCompletedOnboarding
        )

        setupBindings()
        performStartup()
    }

    // MARK: - Startup

    private func performStartup() {
        AudioRecorder.cleanupOrphanedFiles()
        permissionsManager.refresh()

        if !hasCompletedOnboarding {
            showOnboarding = true
        } else {
            ensureHotkeyRegistered()
        }
    }

    /// Attempts hotkey registration, requesting Input Monitoring if needed,
    /// and retrying after a short delay to let TCC propagate.
    func ensureHotkeyRegistered() {
        // First attempt
        shortcutManager.register()

        if shortcutManager.isRegistered {
            Logger.app.info("Hotkey registered on first attempt")
            return
        }

        // If not registered, request Input Monitoring permission (shows system prompt once)
        if !permissionsManager.inputMonitoringGranted {
            Logger.app.info("Requesting Input Monitoring access for hotkey tap")
            permissionsManager.requestInputMonitoring()
        }

        // Retry with escalating delays — TCC grant propagation can take a moment
        Task { @MainActor in
            for delay in [0.5, 1.0, 2.0, 4.0] {
                try? await Task.sleep(for: .seconds(delay))
                permissionsManager.refresh()
                shortcutManager.register()
                if shortcutManager.isRegistered {
                    Logger.app.info("Hotkey registered after \(delay)s retry")
                    return
                }
            }
            Logger.app.warning("Hotkey registration failed after all retries")
        }
    }

    // MARK: - Bindings

    private func setupBindings() {
        shortcutManager.onRecordingStart = { [weak self] in
            Task { @MainActor in
                self?.handleHotkeyPressed()
            }
        }

        shortcutManager.onRecordingStop = { [weak self] in
            Task { @MainActor in
                await self?.handleHotkeyReleased()
            }
        }

        permissionsManager.$inputMonitoringGranted
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, self.hasCompletedOnboarding else { return }
                self.shortcutManager.register()
            }
            .store(in: &cancellables)

        permissionsManager.$accessibilityGranted
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, self.hasCompletedOnboarding else { return }
                self.shortcutManager.register()
            }
            .store(in: &cancellables)

        $dictationState
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshOverlay()
            }
            .store(in: &cancellables)

        audioRecorder.$audioLevel
            .throttle(for: .milliseconds(40), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                guard self?.dictationState == .listening else { return }
                self?.refreshOverlay()
            }
            .store(in: &cancellables)
    }

    private func handleHotkeyPressed() {
        switch shortcutManager.hotkeyMode {
        case .pushToTalk:
            startDictation()
        case .toggleToTalk:
            if dictationState == .listening {
                Task { await stopDictation() }
            } else if dictationState == .idle {
                startDictation()
            }
        }
    }

    private func handleHotkeyReleased() async {
        guard shortcutManager.hotkeyMode == .pushToTalk else { return }
        await stopDictation()
    }

    // MARK: - Dictation Lifecycle

    func startDictation() {
        guard dictationState == .idle else { return }
        permissionsManager.refresh()

        guard shortcutManager.isRegistered || permissionsManager.inputMonitoringGranted else {
            lastError = "Input Monitoring permission required"
            dictationState = .error(message: "Input Monitoring permission required. Open System Settings → Privacy & Security → Input Monitoring.")
            Logger.app.warning("Cannot start dictation — hotkey/input monitoring not ready")
            return
        }

        // Request microphone permission on first use if not yet determined
        if permissionsManager.microphoneStatus != .authorized {
            Task {
                if permissionsManager.microphoneStatus == .notDetermined {
                    await permissionsManager.requestMicrophone()
                }
                if permissionsManager.microphoneStatus == .authorized {
                    await beginRecording()
                } else {
                    lastError = "Microphone permission denied"
                    dictationState = .error(message: "Microphone access denied. Open System Settings → Privacy → Microphone.")
                }
            }
            return
        }

        Task {
            await beginRecording()
        }
    }

    private func beginRecording() async {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let target = await Task.detached(priority: .userInitiated) {
            FocusedElementService.currentTarget()
        }.value

        do {
            try audioRecorder.startRecording()
            savedInsertionTarget = target
            savedInsertionAppPID = target?.processIdentifier ?? frontmostPID
            dictationState = .listening
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            dictationState = .error(message: error.localizedDescription)
            Logger.app.error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopDictation() async {
        guard dictationState == .listening else { return }

        let cycleStart = CFAbsoluteTimeGetCurrent()

        do {
            let audioURL = try await audioRecorder.stopRecording()
            dictationState = .transcribing

            let result = try await transcriptionService.transcribe(audioURL: audioURL)
            diagnosticsService.recordLatency(result.latencyMs)
            diagnosticsService.recordLastProvider(result.provider, model: result.model)

            // Process text
            let mode = TextProcessingMode(
                rawValue: UserDefaults.standard.string(
                    forKey: SPVoiceConstants.UserDefaultsKeys.textProcessingMode
                ) ?? ""
            ) ?? .rawDictation

            let processedText = try await TextProcessingService.process(result.text, mode: mode)
            dictationState = .inserting

            let autoInsertEnabled = (
                UserDefaults.standard.object(
                    forKey: SPVoiceConstants.UserDefaultsKeys.autoInsertEnabled
                ) as? Bool
            ) ?? true

            let insertionResult: TextInsertionService.InsertionResult
            if autoInsertEnabled {
                // Insert — use saved target if available (survives focus changes)
                insertionResult = await TextInsertionService.insert(
                    processedText,
                    savedTarget: savedInsertionTarget,
                    preferredAppPID: savedInsertionAppPID
                )
            } else {
                insertionResult = TextInsertionService.copyToClipboardOnly(
                    processedText,
                    target: savedInsertionTarget
                )
            }
            savedInsertionTarget = nil
            savedInsertionAppPID = nil

            diagnosticsService.recordInsertionOutcome(
                insertionResult.outcome,
                app: insertionResult.target?.appName,
                role: insertionResult.target?.role,
                bundleID: insertionResult.target?.bundleIdentifier,
                isChromium: insertionResult.target?.isChromium ?? false
            )
            diagnosticsService.incrementSessionCount()

            // If insertion failed, ensure text is on clipboard as safety net
            if case .failed = insertionResult.outcome {
                PasteboardHelper.setClipboardText(processedText)
                Logger.app.info("Insertion failed — text copied to clipboard as safety net")
            }

            // History
            if UserDefaults.standard.bool(forKey: SPVoiceConstants.UserDefaultsKeys.historyEnabled) {
                let entry = HistoryStore.Entry(
                    id: UUID(),
                    timestamp: Date(),
                    text: processedText,
                    provider: result.provider,
                    model: result.model,
                    latencyMs: result.latencyMs
                )
                historyStore.add(entry)
            }

            lastTranscription = processedText
            lastError = nil

            let cycleMs = Int((CFAbsoluteTimeGetCurrent() - cycleStart) * 1000)
            Logger.app.info("Dictation cycle completed in \(cycleMs)ms")

            // Show clipboard-fallback hint in success message when applicable
            let preview: String
            if case .clipboardPasteSuccess = insertionResult.outcome {
                preview = String(processedText.prefix(40)) + " (pasted)"
            } else if case .clipboardCopied = insertionResult.outcome {
                preview = "Copied to clipboard"
            } else if case .failed = insertionResult.outcome {
                preview = "Copied to clipboard"
            } else {
                preview = String(processedText.prefix(50))
            }
            dictationState = .success(preview: preview)
            audioRecorder.cleanupTempFiles()

            // Auto-dismiss success after a delay
            Task {
                try? await Task.sleep(for: .seconds(2))
                if case .success = dictationState {
                    dictationState = .idle
                }
            }
        } catch {
            savedInsertionTarget = nil
            savedInsertionAppPID = nil
            audioRecorder.cleanupTempFiles()
            lastError = error.localizedDescription
            dictationState = .error(message: userFriendlyMessage(for: error))
            diagnosticsService.recordProviderError(error)
            Logger.app.error("Dictation failed: \(error.localizedDescription)")

            // Reset to idle after a delay so the error is visible
            Task {
                try? await Task.sleep(for: .seconds(3))
                if case .error = dictationState {
                    dictationState = .idle
                }
            }
        }
    }

    func cancelDictation() {
        audioRecorder.cancelRecording()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        savedInsertionTarget = nil
        savedInsertionAppPID = nil
        dictationState = .idle
        lastError = nil
    }

    func bringSettingsWindowToFront() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            for delay in [120, 300] {
                try? await Task.sleep(for: .milliseconds(delay))
                Self.raiseSettingsWindowIfNeeded()
            }
        }
    }

    // MARK: - Overlay

    private func refreshOverlay() {
        switch dictationState {
        case .listening:
            overlayWindow.showOverlay(state: dictationState, audioLevel: audioRecorder.audioLevel)
        default:
            overlayWindow.hideOverlay()
        }
    }

    // MARK: - Error Helpers

    private func userFriendlyMessage(for error: Error) -> String {
        if let pe = error as? ProviderError {
            return pe.errorDescription ?? error.localizedDescription
        }
        return error.localizedDescription
    }

    // MARK: - TCC Recovery

    /// Reset TCC state for this app and re-request Input Monitoring.
    /// This helps when the TCC grant is bound to a stale code signature (e.g., after rebuild).
    func resetTCCAndReregister() {
        let bundleID = Bundle.main.bundleIdentifier ?? SPVoiceConstants.bundleIdentifier
        Logger.app.info("Resetting TCC ListenEvent for \(bundleID)")

        // tccutil reset resets the specified service for the given bundle ID
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ListenEvent", bundleID]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            Logger.app.info("tccutil output: \(output) exit=\(process.terminationStatus)")
        } catch {
            Logger.app.error("tccutil failed: \(error.localizedDescription)")
        }

        // Also reset Accessibility for good measure
        let axProcess = Process()
        axProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        axProcess.arguments = ["reset", "Accessibility", bundleID]
        try? axProcess.run()
        axProcess.waitUntilExit()

        // Now request fresh permission
        permissionsManager.refresh()
        permissionsManager.requestInputMonitoring()

        // Retry registration with delays
        ensureHotkeyRegistered()
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        hasCompletedOnboarding = true
        showOnboarding = false
        UserDefaults.standard.set(true, forKey: SPVoiceConstants.UserDefaultsKeys.hasCompletedOnboarding)

        ensureHotkeyRegistered()
    }

    private static func raiseSettingsWindowIfNeeded() {
        guard let window = NSApp.windows.first(where: { window in
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return !title.isEmpty && title.localizedCaseInsensitiveContains("settings")
        }) else { return }

        window.collectionBehavior.insert(.moveToActiveSpace)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}
