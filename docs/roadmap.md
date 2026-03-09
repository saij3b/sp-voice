# SP Voice — Development Roadmap

## Phase 1: Architecture & Planning (Current)
**Goal**: Establish the architecture, project structure, and design documents before writing implementation code.

### Deliverables
- `docs/architecture.md` — full system design
- `docs/provider-abstraction.md` — protocol definitions, per-provider API contracts
- `docs/accessibility-strategy.md` — insertion strategies, fallback logic, known-app table
- `docs/risks-and-unknowns.md` — risk register with mitigations
- `docs/roadmap.md` — this document
- `README.md` — install, permissions, configuration, debugging
- Recommended folder structure

### QA Steps
- Review all docs for internal consistency
- Confirm API contracts match current provider documentation
- Validate that folder structure covers all modules

### Edge Cases & Risks
- Architecture may need revision once implementation reveals constraints
- Provider APIs may have changed since research was done

---

## Phase 2: App Scaffold, Menu Bar, Hotkey, Recording, Credentials
**Goal**: Build the runnable app shell with core infrastructure — no transcription yet.

### What Gets Built
- Xcode project with correct entitlements (no sandbox, hardened runtime, audio input)
- `SPVoiceApp.swift` + `AppDelegate.swift` — menu bar lifecycle with `LSUIElement = true`
- `StatusBarController` — NSStatusItem with icon and dropdown menu
- `SettingsView` — tabbed SwiftUI settings window
- `OnboardingView` — first-launch permission flow
- `PermissionsManager` — microphone and accessibility checks/requests
- `ShortcutManager` — global hotkey via CGEvent tap
- `AudioRecorder` — AVAudioEngine-based recording to temp m4a file
- `CredentialsStore` — Keychain CRUD for provider API keys
- `CredentialEntryView` — UI for adding/editing/removing keys per provider

### QA Steps
- App launches as menu bar icon with no Dock presence
- Settings window opens and closes correctly
- Onboarding prompts for accessibility, then microphone
- Hotkey starts/stops recording (verify with console log)
- Audio file is created in temp directory and is playable
- API keys round-trip through Keychain (store → retrieve → delete)
- Keys are not visible in logs

### Edge Cases & Risks
- Hotkey may conflict with system shortcuts
- `CGEvent` tap requires accessibility permission — handle permission-not-granted state
- `AVAudioEngine` may fail if no input device is connected
- Keychain operations may fail if entitlements are misconfigured

---

## Phase 3: OpenAI Provider, Transcription Pipeline, Overlay
**Goal**: Complete the first end-to-end dictation flow: speak → transcribe → see result.

### What Gets Built
- `TranscriptionProvider` protocol
- `TranscriptionService` — orchestrator
- `OpenAIProvider` — multipart upload to `/v1/audio/transcriptions`
- `ProviderManager` — single-provider auto-default
- Floating overlay window (`NSPanel`, non-activating)
- `OverlayView` — states: listening, transcribing, success, error
- Wire hotkey → record → transcribe → overlay display

### QA Steps
- Record audio, send to OpenAI, receive transcript text
- Overlay shows correct state at each phase
- Invalid API key shows clear error
- Network timeout shows "Transcription timed out"
- Very short recording (<0.3s) is discarded
- Test with both `gpt-4o-transcribe` and `gpt-4o-mini-transcribe`
- Measure and log end-to-end latency

### Edge Cases & Risks
- 429 rate limit needs retry logic
- Audio file > 25 MB needs size check before upload
- Network drops mid-upload — timeout and clean error
- Overlay must not steal focus from the user's active app

---

## Phase 4: Text Insertion via Accessibility
**Goal**: Insert transcribed text into the focused text field in any app.

### What Gets Built
- `FocusedElementService` — detect focused element, role, editability
- `TextInsertionService` — three-strategy insertion chain
- `PasteboardHelper` — save/restore clipboard
- `CGEventHelper` — simulate Cmd+V
- Known-app table with default strategy overrides
- Diagnostics panel showing focused app, element role, insertion strategy

### QA Steps
- Insert into: TextEdit, Notes, Safari, Chrome, Firefox, Slack, VS Code, Terminal
- Verify Strategy 1 (direct AX) works for native controls
- Verify Strategy 3 (clipboard-paste) works for Electron/browser apps
- Verify clipboard is restored after paste fallback
- Verify selected text is replaced
- Test with non-editable target — "copied to clipboard" fallback
- Test with no focused element — "no text field detected"

### Edge Cases & Risks
- Silent AX insertion failure (returns success, no visible effect)
- Clipboard restoration race condition
- Focus changes between transcription and insertion
- Thread blocking if target app is unresponsive

---

## Phase 5: OpenRouter & Gemini Providers, Provider UI
**Goal**: Add remaining providers and full provider management UI.

### What Gets Built
- `OpenRouterProvider` — chat completions with base64 audio
- `GeminiProvider` — generateContent with inline audio
- Provider selection UI (primary, secondary, fallback order)
- Model selection UI per provider
- "Test Connection" button per provider
- Multi-provider ProviderManager logic

### QA Steps
- OpenRouter transcription works with audio-capable models
- Gemini transcription works with `gemini-2.5-flash`
- Provider fallback: primary fails → secondary used
- Model selection persists across restarts
- Test connection validates keys correctly
- Same audio produces reasonable results across all providers

### Edge Cases & Risks
- OpenRouter may not support audio for all models
- Gemini may add unwanted formatting to transcription
- Base64 encoding adds ~33% payload overhead
- Different providers return different punctuation/formatting

---

## Phase 6: Text Processing, History, Launch at Login
**Goal**: Add optional text cleanup, local history, and polish features.

### What Gets Built
- `TextProcessingService` — Raw, Polished, Prompt, Custom modes
- Processing settings UI
- `HistoryStore` — local store of recent dictations
- History view with copy and re-insert
- Launch at login toggle
- Retry/cancel flows

### QA Steps
- Each processing mode works as expected
- History records entries with correct metadata
- Copy-to-clipboard and re-insert from history work
- Launch at login persists across reboot
- Cancel mid-transcription returns to idle

### Edge Cases & Risks
- Text processing adds latency
- Polished mode may over-correct technical terms
- Launch at login API varies by macOS version

---

## Phase 7: Testing, Hardening, Polish
**Goal**: Comprehensive testing, edge case fixes, UX refinements.

### QA Matrix
- Native apps: TextEdit, Notes, Pages, Xcode, Mail, Messages
- Browsers: Safari, Chrome, Firefox, Arc
- Electron apps: Slack, VS Code, Discord, Notion
- Terminals: Terminal.app, iTerm2, Warp
- Special cases: Spotlight, Finder rename, login fields

### Edge Cases to Verify
- Dictate while screen is locked
- Dictate in full-screen app (overlay still visible)
- Unplug microphone mid-recording
- Empty transcript from provider
- Hotkey held >5 minutes → auto-stop
- System sleep during transcription
- Multiple monitors → overlay on correct screen