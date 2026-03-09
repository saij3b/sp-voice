import AppKit
import ApplicationServices
import Foundation
import os

/// Inserts text into the currently focused element using a layered strategy chain:
/// 1. Direct AX insertion via `kAXSelectedTextAttribute`
/// 2. AX value splice via `kAXValueAttribute`
/// 3. Clipboard paste fallback via Cmd+V
///
/// Chromium-based browsers bypass AX strategies entirely and go straight to clipboard paste,
/// because Chromium's AX implementation does not support reliable programmatic text insertion.
enum TextInsertionService {

    /// Timing profile for the clipboard paste fallback, tuned per app family.
    private struct PasteProfile {
        let activationDelayMs: Int
        let prePasteDelayMs: Int
        let restoreDelay: TimeInterval
        let eventTapLocation: CGEventTapLocation
        let keyPressDelay: TimeInterval
    }

    /// Result of an insertion attempt, pairing the outcome with the detected target.
    struct InsertionResult {
        let outcome: InsertionOutcome
        let target: FocusedTarget?
    }

    static func copyToClipboardOnly(_ text: String, target: FocusedTarget?) -> InsertionResult {
        PasteboardHelper.setClipboardText(text)
        Logger.insertion.info(
            "Copied transcript to clipboard without paste (app=\(target?.appName ?? "unknown") role=\(target?.role ?? "unknown"))"
        )
        return InsertionResult(outcome: .clipboardCopied, target: target)
    }

    // MARK: - Main Entry Point

    /// Insert text into the current focused element, trying strategies in order.
    /// If `savedTarget` is provided (captured before transcription), it is preferred
    /// over re-detecting the focused element, which guards against focus changes.
    static func insert(
        _ text: String,
        savedTarget: FocusedTarget? = nil,
        preferredAppPID: pid_t? = nil
    ) async -> InsertionResult {
        Logger.insertion.info("Inserting text (\(text.count) chars)")

        let appPID = preferredAppPID ?? savedTarget?.processIdentifier
        let bundleID = savedTarget?.bundleIdentifier ?? runningAppBundleIdentifier(for: appPID)
        let isChromium = savedTarget?.isChromium
            ?? (bundleID.map { FocusedElementService.chromiumBundleIDs.contains($0) } ?? false)

        // ── Chromium fast-path ──────────────────────────────────────────────
        // AX insertion NEVER works in Chromium web views. Go straight to
        // clipboard paste to avoid wasting time and risking stale AX refs.
        if isChromium {
            Logger.insertion.info("Chromium detected (\(bundleID ?? "?")) — using direct paste path")
            return await chromiumPaste(
                text: text,
                savedTarget: savedTarget,
                appPID: appPID,
                bundleID: bundleID
            )
        }

        // ── Standard path for native apps ──────────────────────────────────
        let profile = pasteProfile(bundleID: bundleID)
        await reactivateTargetAppIfNeeded(
            processIdentifier: appPID,
            activationDelayMs: profile.activationDelayMs
        )

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
            Logger.insertion.warning("No focused element — attempting clipboard paste fallback")
            if let appPID {
                return await clipboardFallback(
                    text: text,
                    target: nil,
                    preferredAppPID: appPID,
                    profile: profile
                )
            }
            return copyToClipboardOnly(text, target: nil)
        }

        // Guard: element is editable (try clipboard fallback for non-editable targets)
        guard target.isEditable else {
            Logger.insertion.warning(
                "Target not editable (app=\(target.appName) role=\(target.role)) — falling back to clipboard paste"
            )
            return await clipboardFallback(
                text: text,
                target: target,
                preferredAppPID: target.processIdentifier,
                profile: pasteProfile(bundleID: target.bundleIdentifier)
            )
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
        return await clipboardFallback(
            text: text,
            target: target,
            preferredAppPID: target.processIdentifier,
            profile: pasteProfile(bundleID: target.bundleIdentifier)
        )
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

    // MARK: - Chromium Paste Path

    /// Dedicated insertion path for Chromium-based browsers.
    /// Skips all AX strategies (they never work in web views) and uses a hardened
    /// paste flow with:
    ///   1. Re-activate target app
    ///   2. Re-probe focus to verify we're in the right place
    ///   3. Generous timing for Chromium's async clipboard handling
    ///   4. Double-tap paste as fallback
    private static func chromiumPaste(
        text: String,
        savedTarget: FocusedTarget?,
        appPID: pid_t?,
        bundleID: String?
    ) async -> InsertionResult {
        let profile = pasteProfile(bundleID: bundleID)

        // Step 1: Re-activate the target app
        await reactivateTargetAppIfNeeded(
            processIdentifier: appPID,
            activationDelayMs: profile.activationDelayMs
        )

        // Step 2: Re-probe focus right now (saved target may be stale)
        let liveTarget: FocusedTarget?
        if let appPID {
            liveTarget = await Task.detached {
                FocusedElementService.reprobeTarget(pid: appPID)
            }.value
        } else {
            liveTarget = savedTarget
        }

        let reportTarget = liveTarget ?? savedTarget

        if let live = liveTarget {
            Logger.insertion.info(
                "Chromium reprobe: role=\(live.role) subRole=\(live.subRole ?? "nil") app=\(live.appName)"
            )
        } else {
            Logger.insertion.warning(
                "Chromium reprobe: no focus found — proceeding with blind paste (PID=\(appPID.map { String($0) } ?? "nil"))"
            )
        }

        // Step 3: Set clipboard and paste
        let saved = PasteboardHelper.saveClipboard()
        PasteboardHelper.setClipboardText(text)

        // Pre-paste delay lets Chromium process the clipboard change
        try? await Task.sleep(for: .milliseconds(profile.prePasteDelayMs))

        CGEventHelper.simulatePaste(
            tapLocation: profile.eventTapLocation,
            keyPressDelay: profile.keyPressDelay
        )

        // Step 4: Wait for paste to be processed, then restore clipboard
        try? await Task.sleep(for: .seconds(profile.restoreDelay))

        PasteboardHelper.restoreClipboard(saved)

        Logger.insertion.info(
            "Chromium paste completed (app=\(reportTarget?.appName ?? "unknown") role=\(reportTarget?.role ?? "unknown") bundle=\(bundleID ?? "unknown"))"
        )
        return InsertionResult(outcome: .clipboardPasteSuccess, target: reportTarget)
    }

    // MARK: - Strategy 3: Clipboard Paste Fallback (generic)

    /// Save clipboard → set text → simulate Cmd+V → restore clipboard.
    /// Universal fallback that works in virtually all apps.
    private static func clipboardFallback(
        text: String,
        target: FocusedTarget?,
        preferredAppPID: pid_t?,
        profile: PasteProfile
    ) async -> InsertionResult {
        await reactivateTargetAppIfNeeded(
            processIdentifier: preferredAppPID,
            activationDelayMs: profile.activationDelayMs
        )

        let saved = PasteboardHelper.saveClipboard()
        PasteboardHelper.setClipboardText(text)

        if profile.prePasteDelayMs > 0 {
            try? await Task.sleep(for: .milliseconds(profile.prePasteDelayMs))
        }

        CGEventHelper.simulatePaste(
            tapLocation: profile.eventTapLocation,
            keyPressDelay: profile.keyPressDelay
        )

        // Wait for the paste event to be processed by the target app
        try? await Task.sleep(for: .seconds(profile.restoreDelay))

        PasteboardHelper.restoreClipboard(saved)

        Logger.insertion.info(
            "Clipboard paste fallback used (app=\(target?.appName ?? "unknown") role=\(target?.role ?? "unknown"))"
        )
        return InsertionResult(outcome: .clipboardPasteSuccess, target: target)
    }

    // MARK: - Helpers

    private static func reactivateTargetAppIfNeeded(
        processIdentifier: pid_t?,
        activationDelayMs: Int
    ) async {
        guard let processIdentifier, processIdentifier > 0,
              let app = NSRunningApplication(processIdentifier: processIdentifier) else {
            return
        }

        guard !app.isActive else { return }

        Logger.insertion.debug("Reactivating target app before insertion: \(app.localizedName ?? "unknown")")
        app.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(for: .milliseconds(activationDelayMs))
    }

    private static func pasteProfile(bundleID: String?) -> PasteProfile {
        // Universal default — robust enough for ANY app (native, Catalyst, Electron, etc.).
        // Uses .cgAnnotatedSessionEventTap which is more universally accepted than .cghidEventTap,
        // with generous-enough timing that virtually all apps process the paste in time.
        let defaultProfile = PasteProfile(
            activationDelayMs: 150,
            prePasteDelayMs: 50,
            restoreDelay: 0.5,
            eventTapLocation: .cgAnnotatedSessionEventTap,
            keyPressDelay: 0.025
        )

        guard let bundleID else { return defaultProfile }

        // ── Chromium browsers ──────────────────────────────────────────────
        // Need the most generous timing: Chromium's async clipboard handling
        // and multi-process architecture require extra delays at every step.
        if FocusedElementService.chromiumBundleIDs.contains(bundleID) {
            return PasteProfile(
                activationDelayMs: 250,
                prePasteDelayMs: 100,
                restoreDelay: 1.0,
                eventTapLocation: .cgAnnotatedSessionEventTap,
                keyPressDelay: 0.035
            )
        }

        // ── Electron / Catalyst / hybrid apps ──────────────────────────────
        // Not Chromium browsers, but still non-native. Slightly more generous
        // than the default to account for cross-process clipboard handling.
        if electronAndHybridBundleIDs.contains(bundleID) {
            return PasteProfile(
                activationDelayMs: 200,
                prePasteDelayMs: 80,
                restoreDelay: 0.6,
                eventTapLocation: .cgAnnotatedSessionEventTap,
                keyPressDelay: 0.030
            )
        }

        return defaultProfile
    }

    /// Known Electron, Catalyst, and hybrid-framework app bundle IDs.
    /// These apps need slightly more generous paste timing than pure Cocoa apps.
    private static let electronAndHybridBundleIDs: Set<String> = [
        // Electron apps
        "com.tinyspeck.slackmacgap",        // Slack
        "com.microsoft.VSCode",              // VS Code
        "com.hnc.Discord",                   // Discord
        "com.bitwarden.desktop",             // Bitwarden
        "com.electron.lark",                 // Lark (Electron variant)
        "com.anthropic.claudefordesktop",    // Claude Desktop
        "com.openai.chat",                   // ChatGPT Desktop
        "com.openai.codex",                  // Codex
        "com.linear",                        // Linear
        "com.figma.Desktop",                 // Figma
        "com.spotify.client",               // Spotify
        "com.hnc.Discord.Canary",           // Discord Canary
        "com.1password.1password",           // 1Password
        // Catalyst / hybrid / cross-platform
        "net.whatsapp.WhatsApp",             // WhatsApp (Catalyst)
        "ru.keepcoder.Telegram",             // Telegram
        "com.tencent.xinWeChat",             // WeChat
        "com.larksuite.macos.lark",          // Lark (native variant)
        "ai.perplexity.comet",               // Perplexity
        "com.microsoft.Outlook",             // Outlook
        "com.microsoft.teams2",              // Teams
        "com.facebook.archon",               // Messenger
    ]

    private static func runningAppBundleIdentifier(for processIdentifier: pid_t?) -> String? {
        guard let processIdentifier, processIdentifier > 0 else { return nil }
        return NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
    }
}
