# Risks and Unknowns

## High Risk

### 1. Text Insertion Reliability Across Apps
**Risk**: The macOS Accessibility API (`AXUIElement`) behaves inconsistently across apps. Electron apps (Slack, VS Code, Discord), browser contentEditable fields (Chrome, Firefox), and terminal emulators do not reliably support `kAXSelectedTextAttribute` insertion.

**Impact**: Users will experience failed insertions in popular apps, leading to frustration and the perception that the app is broken.

**Mitigation**:
- Three-tier fallback strategy: direct AX → AX value replacement → clipboard-paste
- Maintain a known-app table mapping bundle IDs to preferred strategies
- Default to clipboard-paste for known problematic apps
- Always offer "copied to clipboard" as a last-resort fallback
- Surface diagnostic info so users understand why insertion failed

**Residual risk**: Clipboard-paste briefly clobbers the user's clipboard. Some apps may not respond to simulated `Cmd+V` (e.g., apps that disable paste in certain contexts).

### 2. Accessibility Permission UX on macOS
**Risk**: macOS requires Accessibility permission for global hotkey detection and text insertion. The permission grant process is clunky — the user must navigate to System Settings manually, and on some macOS versions the app must be relaunched after granting.

**Impact**: First-time setup friction. Users may grant the permission but the app doesn't detect it, leading to confusion.

**Mitigation**:
- Clear onboarding flow with step-by-step guidance
- Poll `AXIsProcessTrusted()` on a 1-second timer to detect grants without restart
- Show a "restart required" message if polling doesn't pick up the change
- Deep-link to the correct System Settings pane

### 3. Hotkey Conflicts
**Risk**: The default `Option+Space` may conflict with Spotlight, Alfred, Raycast, or other global hotkey apps. `CGEvent` tap may not receive the event if another app consumes it first.

**Impact**: Hotkey doesn't trigger, or triggers multiple apps simultaneously.

**Mitigation**:
- Make the hotkey fully configurable in Settings
- Detect conflicts at registration time and warn the user
- Support both modifier+key combos and multi-key shortcuts
- Document common conflicts in the troubleshooting guide

---

## Medium Risk

### 4. OpenRouter Audio Transcription Quality
**Risk**: OpenRouter's transcription path uses chat completions with audio input, not a dedicated STT endpoint. Transcription quality depends on the system prompt and the underlying model. Some models may add commentary, formatting, or translations instead of faithful transcription.

**Impact**: Inconsistent or incorrect transcriptions when using the OpenRouter provider.

**Mitigation**:
- Carefully crafted system prompt: "Transcribe exactly as spoken. Output only the transcription."
- Test across multiple OpenRouter audio models and select reliable defaults
- Allow users to customize the transcription prompt per provider
- Document which OpenRouter models work best for dictation

### 5. Gemini Prompt-Driven Transcription
**Risk**: Similar to OpenRouter — Gemini has no dedicated STT API. Transcription is achieved by sending audio to `generateContent` with a text instruction. The model may hallucinate, add punctuation differently, or miss words.

**Impact**: Lower transcription accuracy compared to OpenAI's dedicated model.

**Mitigation**:
- Iterate on the instruction prompt for Gemini
- Compare transcription quality across providers in integration tests
- Document accuracy trade-offs for each provider in the app's help text
- Allow temperature control for Gemini to reduce hallucination

### 6. Audio Recording Latency
**Risk**: `AVAudioEngine` setup time could add perceptible delay between hotkey press and actual recording start. If the first ~100ms of speech is lost, transcription quality suffers.

**Impact**: Clipped beginnings of phrases ("he quick brown fox" instead of "The quick brown fox").

**Mitigation**:
- Keep `AVAudioEngine` initialized and warm (pre-allocate the tap, just start/stop the engine)
- Buffer a small amount of audio before the hotkey press using a rolling buffer
- Measure setup latency in diagnostics
- If latency is consistently >200ms, pre-start the engine on app launch and pause/resume instead of full start/stop

### 7. App Not Distributed via App Store
**Risk**: Since App Sandbox must be disabled, the app cannot be distributed through the Mac App Store. Distribution requires Developer ID signing and notarization.

**Impact**: Users must download from a website or GitHub, and macOS Gatekeeper may warn about "unidentified developer" if notarization is incomplete.

**Mitigation**:
- Sign with a Developer ID certificate
- Notarize with `notarytool` before distribution
- Provide clear installation instructions for bypassing Gatekeeper warnings
- Consider a Homebrew cask for easier installation

---

## Low Risk

### 8. Provider API Changes
**Risk**: OpenAI, OpenRouter, or Gemini could change their API contracts, deprecate models, or alter pricing.

**Impact**: Provider adapter breaks; transcription fails until code is updated.

**Mitigation**:
- Pin to known-stable API versions where possible
- Provider validation (`validateCredentials`) will surface API errors early
- Modular provider design means only the affected adapter needs updating
- Monitor provider changelogs

### 9. Clipboard Restoration Failure
**Risk**: The clipboard-paste fallback saves and restores clipboard contents. If the app crashes between paste and restore, the user's clipboard is lost.

**Impact**: User loses clipboard contents (annoying but not catastrophic).

**Mitigation**:
- Keep the save/restore window as short as possible (~150ms)
- Check pasteboard change count before restoring to avoid overwriting user's new copy
- Accept this as a known trade-off of the clipboard fallback strategy

### 10. Audio File Cleanup
**Risk**: Temporary audio files may accumulate if the app crashes before cleanup.

**Impact**: Disk space usage grows over time with orphaned temp files.

**Mitigation**:
- Write to `NSTemporaryDirectory()` (OS cleans periodically)
- On each launch, scan for and delete orphaned SP Voice audio files
- Name files with a unique prefix (e.g., `spvoice_recording_*.m4a`) for easy identification

### 11. macOS Version Compatibility
**Risk**: Accessibility API behavior varies across macOS versions. A strategy that works on Sonoma may break on Sequoia or future releases.

**Impact**: Insertion failures on newer macOS versions.

**Mitigation**:
- Target macOS 14+ (Sonoma) as minimum
- Test on the latest macOS beta before release
- Use runtime version checks if behavior differs between versions

---

## Open Questions

1. **Rolling audio buffer**: Should we maintain a 0.5s rolling audio buffer to capture speech that starts slightly before the hotkey press? This adds complexity but improves transcription of fast speakers.

2. **Insertion verification**: After AX insertion, should we re-read the focused element's value to verify the text was actually inserted? This adds latency but catches silent failures.

3. **Audio format per provider**: Should the `AudioRecorder` produce different formats per provider (m4a for OpenAI, wav for Gemini/OpenRouter), or standardize on one format? Standardizing is simpler; per-provider is marginally more efficient.

4. **Text processing provider**: Should the text processing modes (Polished Writing, Prompt Mode) use the same provider as transcription, or a separate chat model? Using the same key simplifies configuration; using a separate model allows optimization (e.g., cheap model for transcription, smart model for polishing).

5. **Overlay positioning**: Should the overlay follow the cursor/focused element, or stay in a fixed screen position? Fixed is simpler; cursor-following is more polished but complex.

6. **Concurrent dictation sessions**: Should the app support starting a new dictation while the previous one is still transcribing? Queuing is safer; concurrent is more responsive.
