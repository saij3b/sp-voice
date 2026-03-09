# SP Voice — Architecture Document

## 1. Overview

SP Voice is a native macOS menu bar app that provides global push-to-talk dictation. The user holds a hotkey, speaks, and the app transcribes the audio via a cloud provider (OpenAI, OpenRouter, or Gemini) and inserts the resulting text into whatever text field is currently focused — in any app or browser.

### Design Principles
- **Reliability over features**: every dictation cycle must complete or fail cleanly.
- **Low friction**: hotkey → speak → text appears. No windows, no clicks.
- **Bring your own key**: no server-side accounts, no subscriptions, no cloud sync.
- **Modular provider layer**: adding a new transcription backend should require only a new conformance to a single protocol.
- **Security by default**: secrets in Keychain, no raw key logging, minimal audio retention.

### Technology Stack
- **Language**: Swift 5.9+
- **UI**: SwiftUI (settings, onboarding) + AppKit (menu bar, overlay window, NSPanel)
- **Audio**: AVFoundation (AVAudioEngine for low-latency capture)
- **Accessibility**: ApplicationServices / AXUIElement C API bridged to Swift
- **Networking**: Foundation URLSession (async/await)
- **Storage**: macOS Keychain (secrets), UserDefaults / JSON file (preferences), SQLite or JSON file (history)
- **Build**: Xcode project (not SPM-only, because we need entitlements, Info.plist, code signing, and menu bar lifecycle)
- **Minimum deployment target**: macOS 14 (Sonoma)

---

## 2. High-Level Data Flow

```
┌──────────────┐    hotkey     ┌────────────────┐   audio    ┌─────────────────┐
│ ShortcutMgr  │──────────────▶│ AudioRecorder  │──────────▶│ TranscriptionSvc│
└──────────────┘               └────────────────┘           └────────┬────────┘
                                                                     │ text
                                                                     ▼
┌──────────────┐  insert text  ┌────────────────┐  optional  ┌──────────────────┐
│ TextInsertion│◀──────────────│ TextProcessing │◀───────────│ ProviderManager  │
│   Service    │               │   Service      │            └──────────────────┘
└──────┬───────┘               └────────────────┘
       │
       ▼
  Focused text field in any macOS app
```

**Sequence (push-to-talk)**:
1. User presses hotkey → `ShortcutManager` fires `startRecording`.
2. `AudioRecorder` captures microphone input to a temp file (m4a/wav).
3. User releases hotkey → `ShortcutManager` fires `stopRecording`.
4. `TranscriptionService` asks `ProviderManager` for the active provider.
5. Provider uploads audio → returns transcript.
6. If a text-processing mode is active, `TextProcessingService` transforms the text.
7. `FocusedElementService` resolves the current target.
8. `TextInsertionService` inserts text via Accessibility API (primary) or clipboard-paste (fallback).
9. Overlay shows success/failure; entry is saved to `HistoryStore`.

---

## 3. Module Responsibilities

### 3.1 AppShell
**Owner of the application lifecycle.**

- Menu bar presence: `NSApplication` with `LSUIElement = true`; status bar item with SF Symbol icon
- Settings window: SwiftUI `Window` scene, opened from menu bar
- Onboarding: first-launch flow — permissions → credentials → test dictation
- Overlay: `NSPanel` (floating, non-activating, level = `.floating`) that shows recording / transcribing / inserting / done / error states
- State coordination: holds references to all services; wires events via Combine or async streams

Key AppKit requirement: the overlay must be an `NSPanel` with `styleMask: [.nonactivatingPanel]` and `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]` so it never steals focus from the user's active app.

### 3.2 ShortcutManager
Registers a global keyboard shortcut using `CGEvent` tap or the `NSEvent.addGlobalMonitorForEvents` API.

- Default hotkey: `Option + Space`
- Configurable via Settings
- Detects key-down (start recording) and key-up (stop recording) for push-to-talk
- Future: toggle-to-talk mode (press once to start, press again to stop)
- Must work even when the app is not frontmost
- Requires Accessibility permission for global event monitoring via `CGEvent` tap

**Implementation approach**: `CGEvent` tap is preferred over `NSEvent.addGlobalMonitorForEvents` because the latter cannot detect key-up events for modifier-only shortcuts. A `CGEvent` tap at `kCGAnnotatedSessionEventTap` requires Accessibility permission.

### 3.3 AudioRecorder
Wraps `AVAudioEngine` for low-latency microphone capture.

- Checks `AVCaptureDevice.authorizationStatus(for: .audio)` before recording
- Installs a tap on the input node; writes PCM to a buffer
- On stop, exports to a temporary `.m4a` or `.wav` file (provider-dependent format preference)
- Cleans up temp files after successful transcription
- Exposes audio level meter values for the overlay VU indicator
- Handles cancel (user aborts mid-recording)
- Configurable sample rate (default 16 kHz mono — sufficient for speech, small file size)

### 3.4 ProviderManager
Registry and router for transcription providers.

- Maintains an ordered list of configured providers
- Auto-defaults: if exactly one provider key is stored, that provider is primary
- If multiple keys exist, user must explicitly set primary and (optionally) secondary
- Exposes `activeProvider` (resolves primary → secondary → first available)
- Validates provider health: key format check + lightweight API ping
- Persists provider preference in UserDefaults
- Emits provider-change events for UI binding

### 3.5 TranscriptionService
Provider-agnostic orchestrator.

- Accepts audio file URL → returns `TranscriptionResult`
- Calls `ProviderManager.activeProvider.transcribe(audioURL:)`
- If primary fails, retries with secondary provider (if configured)
- Measures end-to-end latency
- Returns structured result: text, provider, model, language, latencyMs, rawMetadata

### 3.6 TextProcessingService
Optional post-transcription transform layer.

Modes:
- **Raw Dictation**: no processing, insert as-is
- **Polished Writing**: capitalize sentences, fix punctuation, remove filler words
- **Prompt Mode**: wraps the transcript in a system prompt and sends to a chat model
- **Custom Transform**: user-defined system prompt

Can be disabled entirely. Architecturally this is a `(String) async throws -> String` pipeline stage.

### 3.7 FocusedElementService
Uses macOS Accessibility APIs to inspect the current input target.

- Creates system-wide element via `AXUIElementCreateSystemWide()`
- Reads `kAXFocusedUIElementAttribute` to get the focused element
- Reads element `kAXRoleAttribute` to determine type
- Determines editability: checks if `kAXValueAttribute` is settable, or `kAXSelectedTextAttribute` exists
- Reads `kAXSelectedTextRangeAttribute` if text is selected
- Resolves frontmost app name via `NSWorkspace.shared.frontmostApplication`
- Exposes a normalized `FocusedTarget` (appName, bundleIdentifier, element, role, isEditable, hasSelection, selectionRange)

### 3.8 TextInsertionService
Inserts transcribed text into the focused element. This is the most complex and fragile module.

**Strategy chain** (tried in order):
1. **Direct AX insertion**: set `kAXSelectedTextAttribute` on the focused element. Works for native NSTextField, NSTextView, and most standard controls.
2. **AX value replacement**: read current `kAXValueAttribute`, compute insertion point from `kAXSelectedTextRangeAttribute`, splice text, set `kAXValueAttribute`. Required for some combo boxes.
3. **Clipboard-paste fallback**: save pasteboard, set pasteboard to new text, simulate `Cmd+V` via `CGEvent`, restore pasteboard after ~100ms delay.

Returns an `InsertionOutcome` (directAXSuccess, axValueReplaceSuccess, clipboardPasteSuccess, or failed with error).

Logging: every attempt logs strategy used, target app, element role, and error (if any).

### 3.9 CredentialsStore
Thin wrapper over macOS Keychain Services.

- Store/retrieve/delete API keys keyed by provider ID
- Uses `kSecClassGenericPassword` with service = "com.spvoice.credentials"
- Never returns raw key in log output
- Supports "test connection" by calling a lightweight provider endpoint
- Validates key format before storing (e.g., OpenAI keys start with `sk-`)

### 3.10 PermissionsManager
Guides the user through required macOS permissions.

**Microphone**:
- Check: `AVCaptureDevice.authorizationStatus(for: .audio)`
- Request: `AVCaptureDevice.requestAccess(for: .audio)`
- If denied: show alert with deep link to System Settings → Privacy & Security → Microphone

**Accessibility**:
- Check: `AXIsProcessTrusted()`
- Prompt: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`
- If denied: show alert with guidance to System Settings → Privacy & Security → Accessibility
- Poll for permission grant (1-second timer) so the app reacts immediately when the user toggles the permission

### 3.11 HistoryStore
Local-only store of recent dictation entries.

- Stores last N entries (default 100)
- Each entry: timestamp, text, provider, model, latency, insertion outcome
- Backed by a JSON file or SQLite
- Supports copy-to-clipboard and re-insert for any entry
- Can be disabled entirely in Settings

### 3.12 Diagnostics
Structured logging and debug inspection.

- Uses `os.Logger` with subsystem "com.spvoice" and per-module categories
- Logs: provider request/response timing, insertion strategy and outcome, focused app/element info, permission state changes
- Last-error surface: stores last provider error and last insertion error for display in Settings → Diagnostics
- Focused-app inspector: shows current frontmost app, focused element role, and editability
- End-to-end latency: measures hotkey-down → text-inserted timestamp delta

---

## 4. Provider Abstraction Design

### 4.1 Protocol

```swift
protocol TranscriptionProvider {
    var id: ProviderID { get }
    var displayName: String { get }
    var supportedModels: [TranscriptionModel] { get }
    var defaultModel: TranscriptionModel { get }

    func validateCredentials() async throws
    func transcribe(
        audioURL: URL,
        model: TranscriptionModel?,
        options: TranscriptionOptions?
    ) async throws -> TranscriptionResult
}

enum ProviderID: String, Codable, CaseIterable {
    case openai
    case openrouter
    case gemini
}
```

### 4.2 OpenAI Provider

- **Endpoint**: `POST https://api.openai.com/v1/audio/transcriptions`
- **Auth**: `Authorization: Bearer <key>`
- **Content-Type**: `multipart/form-data`
- **Fields**: `file`, `model` ("gpt-4o-transcribe" or "gpt-4o-mini-transcribe"), `response_format` ("json"), optional `prompt`, optional `language`
- **Response**: `{ "text": "..." }`
- **Default model**: `gpt-4o-transcribe`
- **Fallback model**: `gpt-4o-mini-transcribe`
- **Validation**: `GET /v1/models` — 200 = valid key
- **Supported audio formats**: mp3, mp4, mpeg, mpga, m4a, wav, webm (max 25 MB)
- **Preferred recording format**: m4a (AAC) at 16 kHz mono

### 4.3 OpenRouter Provider

- **Endpoint**: `POST https://openrouter.ai/api/v1/chat/completions`
- **Auth**: `Authorization: Bearer <key>`
- **Body**: chat completions with `input_audio` content part (base64-encoded audio)
- **Response**: `choices[0].message.content` contains transcript text
- **Model selection**: user picks from audio-capable models (e.g., `openai/gpt-4o-audio-preview`)
- **Validation**: `GET /api/v1/models` — check for 200
- **Key difference**: chat-completions-based transcription, not a dedicated endpoint. System prompt instructs the model to transcribe faithfully.

### 4.4 Gemini Provider

- **Endpoint**: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- **Auth**: `?key=<api_key>` query parameter
- **Body**: `contents` with inline audio data (base64) + transcription instruction text part
- **Response**: `candidates[0].content.parts[0].text`
- **Model selection**: `gemini-2.5-flash` (fast) or `gemini-2.5-pro` (higher accuracy)
- **Validation**: trivial `generateContent` call and check for 200
- **Supported formats**: WAV, MP3, AIFF, AAC, OGG, FLAC (max 20 MB inline)
- **Key difference**: transcription is prompt-driven — quality depends on instruction prompt.

---

## 5. Text Insertion Strategy (Accessibility)

### 5.1 Requirements

- **Disabled App Sandbox**: Accessibility APIs do not work from a sandboxed app.
- **Code-signed**: required for Accessibility trust.
- **Accessibility permission**: user must grant in System Settings → Privacy & Security → Accessibility.

### 5.2 Strategy Chain

#### Strategy 1: Direct AX Selected-Text Insertion (preferred)

1. `AXUIElementCreateSystemWide()`
2. `AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute)` → focusedElement
3. Check role ∈ {kAXTextFieldRole, kAXTextAreaRole}
4. `AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextAttribute, text)`

Works for: native NSTextField, NSTextView, Safari address bar, most Cocoa controls.
Does NOT work for: some Electron apps, kAXComboBoxRole, kAXWebAreaRole (varies by browser).

#### Strategy 2: AX Value Replacement

For elements where `kAXSelectedTextAttribute` is not supported but `kAXValueAttribute` is settable:
1. Read current `kAXValueAttribute`
2. Read `kAXSelectedTextRangeAttribute` for insertion point
3. Splice new text at insertion point
4. Set `kAXValueAttribute` with updated text

#### Strategy 3: Clipboard-Paste Fallback

1. Save current `NSPasteboard.general` contents
2. Set pasteboard to transcription text
3. Simulate `Cmd+V` via `CGEvent`
4. After ~100ms delay, restore original pasteboard contents

Trade-offs: works almost everywhere, but briefly clobbers clipboard and is timing-sensitive.

### 5.3 App-Specific Workarounds

- **Electron apps** (Slack, Discord, VS Code): AX insertion unreliable → default to clipboard-paste
- **Terminal.app / iTerm2**: AX insertion doesn't work → clipboard-paste
- **Browsers** (contentEditable): inconsistent AX support for kAXWebAreaRole → clipboard-paste

The app maintains a configurable app-behavior table (bundleID → preferred strategy) with user override in Settings → Advanced.

---

## 6. Permissions Plan

### 6.1 Required Permissions

- **Microphone**: record audio. Check via `AVCaptureDevice.authorizationStatus(for: .audio)`. Request via `AVCaptureDevice.requestAccess(for: .audio)`.
- **Accessibility**: global hotkey, focused element detection, text insertion. Check via `AXIsProcessTrusted()`. Prompt via `AXIsProcessTrustedWithOptions(...)`.

### 6.2 Onboarding Flow

```
Launch → Check Accessibility
  ├─ Not granted → Show explanation → Open System Settings prompt
  │                  └─ Poll AXIsProcessTrusted() every 1s until granted
  └─ Granted → Check Microphone
                 ├─ Not determined → Request access
                 ├─ Denied → Show guidance to System Settings
                 └─ Authorized → Check Credentials
                                  ├─ None stored → Show Settings → Credentials tab
                                  └─ At least one → Ready
```

### 6.3 Runtime Checks

Before every recording session:
1. `AXIsProcessTrusted()` — if false, show overlay error
2. `AVCaptureDevice.authorizationStatus(for: .audio)` — if not `.authorized`, show overlay error

---

## 7. Settings & Persistence

### UserDefaults Keys
- `selectedPrimaryProvider`, `selectedSecondaryProvider`, `providerFallbackOrder`
- `modelPerProvider` (dictionary)
- `globalHotkey` (encoded modifier flags + key code)
- `hotkeyMode` (pushToTalk / toggleToTalk)
- `textProcessingMode`, `autoInsertEnabled`
- `historyEnabled`, `launchAtLogin`, `maxHistoryEntries`

### Keychain Items
- Service: `com.spvoice.credentials`
- Account: `openai`, `openrouter`, `gemini`
- Data: API key (UTF-8 encoded)

---

## 8. Overlay States

The floating overlay communicates the current dictation lifecycle:

- **Idle**: hidden
- **Listening**: pulsing mic icon + audio level bars (while hotkey held)
- **Transcribing**: spinner + "Transcribing..." (until API returns)
- **Processing**: spinner + "Processing..." (only if text processing enabled)
- **Inserting**: brief flash (~100ms)
- **Success**: checkmark + brief text preview (auto-dismiss after 1.5s)
- **Error**: red icon + error message (auto-dismiss after 3s, or tap to dismiss)

Overlay position: centered horizontally, near top of screen. Small (~200×60pt).

---

## 9. Error Handling Strategy

### Provider Errors
- Network unreachable → show "No connection"; offer retry
- 401 Unauthorized → show "Invalid API key for {provider}"; link to Settings
- 429 Rate limited → auto-retry with secondary provider
- 500+ Server error → retry once after 1s, then failover to secondary
- Timeout (15s default) → cancel, show "Transcription timed out"

### Insertion Errors
- Accessibility not trusted → show permission prompt
- No focused element → "No text field detected — copied to clipboard"
- Element not editable → "Target is not editable — copied to clipboard"
- AX insertion failed → automatic fallback to clipboard-paste
- All strategies failed → "Could not insert text — copied to clipboard"

### Audio Errors
- Microphone not authorized → show permission guidance
- No audio input device → "No microphone found"
- Recording too short (<0.3s) → discard silently
- Recording too long (>5 min) → auto-stop and transcribe

---

## 10. Security Model

1. **API keys**: stored in macOS Keychain; never in UserDefaults, files, or logs.
2. **Audio files**: written to `NSTemporaryDirectory()`; deleted after transcription. Orphaned files cleaned on next launch.
3. **Clipboard**: original contents saved before paste-fallback and restored within 200ms.
4. **Logging**: `os.Logger` with `privacy: .private` for sensitive fields.
5. **Network**: all provider communication over HTTPS.
6. **No analytics / telemetry**: zero data leaves the machine except provider API calls.

---

## 11. Testing Strategy

### Unit Tests
- Provider request/response serialization and normalization
- Provider selection logic (auto-default, fallback order)
- Text processing transforms
- Credential format validation
- History store CRUD

### Integration Tests (require API keys as env vars)
- End-to-end transcription with each provider
- Provider fallback: mock primary failure, assert secondary is called

### Manual QA Matrix
- Text insertion across: TextEdit, Notes, Safari, Chrome, Firefox, Slack, VS Code, Terminal, Spotlight
- Permission denied states
- Hot-plug microphone during recording
- Rapid repeated dictations (5 sessions in quick succession)
- Long dictation (2+ minutes)
- Empty dictation (press and immediately release)