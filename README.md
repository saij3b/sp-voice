# SP Voice

A native macOS menu bar app for global push-to-talk dictation. Press a hotkey, speak, and the transcribed text is inserted directly into any focused text field — in any app, any browser.

## Features

- **Global push-to-talk**: hold a hotkey to record, release to transcribe and insert
- **Works everywhere**: inserts text into any macOS app or browser text field
- **Bring your own key**: supports OpenAI, OpenRouter, and Gemini API keys
- **Provider fallback**: automatic retry with a secondary provider if the primary fails
- **Floating overlay**: shows a listening overlay while recording
- **Text processing modes**: raw dictation, polished writing, prompt mode, custom transforms
- **Local history**: review and re-insert recent dictations
- **Secure**: API keys stored in macOS Keychain, no telemetry, no cloud sync

## Quick Start

1. Build and run (see Installation below).
2. Grant **Accessibility** and **Microphone** permissions when prompted.
3. Open **Settings → Providers** and enter your API key (OpenRouter `sk-or-...` or OpenAI `sk-...`).
4. Click the menu bar mic icon → verify it shows your provider.
5. Focus a text field, hold **Option + Space**, speak, release. The transcript is inserted into the focused app, with clipboard fallback when direct insertion is unavailable.

### Testing a Dictation Cycle Locally

```
1. Run the app in Xcode (Cmd+R)
2. Grant permissions (Accessibility + Microphone)
3. Enter your API key in Settings → Providers
4. Open TextEdit and focus the text area
5. Hold Option+Space, say "Hello world", release
6. Check: the listening overlay appears while recording and closes as soon as you stop
7. Check: Settings → Diagnostics shows latency and provider info
```

**Models:** The default model is `gpt-4o-transcribe`. You can switch to `gpt-4o-mini-transcribe` (faster, lower cost) in Settings → Providers.

## Requirements

- macOS 14 (Sonoma) or later
- An API key for at least one provider: OpenRouter (default primary), OpenAI, or Gemini
- Microphone (built-in or external)

## Installation

### From Source

**Prerequisites:** Xcode 15+.

```bash
# Clone and open the included Xcode project
git clone https://github.com/youruser/sp-voice.git
cd sp-voice/SPVoice
open SPVoice.xcodeproj
```

Build and run in Xcode (`Cmd+R`). The app will appear as a menu bar icon.

If Xcode asks for signing, choose your own Apple development team under **Signing & Capabilities**. The repository does not include any personal signing identity.

> **Optional:** `project.yml` is included if you prefer regenerating the project with XcodeGen, but the checked-in `.xcodeproj` is ready to open directly.

### Pre-built Binary

Download the latest `.dmg` from the Releases page. Drag SP Voice to Applications.

On first launch, macOS may warn about an unidentified developer. Right-click the app → Open to bypass Gatekeeper.

## Permissions

SP Voice requires two macOS permissions:

### 1. Accessibility
**Required for**: global hotkey detection, text insertion into other apps.

- On first launch, SP Voice will prompt you to grant Accessibility access.
- Go to **System Settings → Privacy & Security → Accessibility**.
- Toggle SP Voice **on**.
- You may need to restart SP Voice after granting.

### 2. Microphone
**Required for**: recording your speech.

- On first launch, macOS will show a microphone access prompt.
- Click **Allow**.
- If you accidentally deny, go to **System Settings → Privacy & Security → Microphone** and toggle SP Voice on.

## Configuration

### Adding API Keys

1. Click the SP Voice menu bar icon → **Settings**.
2. Go to the **Providers** tab.
3. Enter your API key for one or more providers:
   - **OpenRouter** (default primary): Get a key at [openrouter.ai](https://openrouter.ai/keys). Prefix: `sk-or-`
   - **OpenAI** (auto-fallback): Get a key at [platform.openai.com](https://platform.openai.com/api-keys). Prefix: `sk-`
   - **Gemini** (optional): Get a key at [aistudio.google.com](https://aistudio.google.com/app/apikey). No standard prefix.
4. Click **Test Connection** to verify each key.
5. If you have multiple providers, choose your **Primary** and optionally a **Secondary** (fallback).

### Provider Fallback

When multiple providers are configured, SP Voice auto-selects the primary by priority: OpenRouter > OpenAI > Gemini. The next-highest-priority configured provider becomes the automatic fallback. If only one provider has a key, it becomes the default automatically. You can override both primary and secondary in Settings → Providers.

**Provider notes:**
- **OpenAI** uses dedicated speech-to-text models (`gpt-4o-transcribe`, `gpt-4o-mini-transcribe`). Best accuracy and lowest latency.
- **OpenRouter** routes audio through chat-completion models with `input_audio` support. Transcription quality varies by model.
- **Gemini** uses `generateContent` with inline audio. Supports `gemini-2.5-flash` and `gemini-2.5-pro`.

### Hotkey

- Default: **Option + Space**
- Change in **Settings → Shortcuts**
- Push-to-talk: hold to record, release to transcribe
- Toggle-to-talk: press once to start, press again to stop

### Text Processing Modes

- **Raw Dictation**: insert exactly as transcribed
- **Polished Writing**: auto-capitalize, fix punctuation, remove filler words
- **Prompt Mode**: send transcript through a chat model with a system prompt
- **Custom Transform**: provide your own prompt for post-processing

Change the mode in **Settings → Processing**.

## Usage

1. Focus a text field in any app (TextEdit, browser, Slack, etc.).
2. Hold **Option + Space**.
3. Speak clearly.
4. Release the hotkey.
5. The listening overlay closes immediately after recording stops.
6. Text appears at your cursor position.

If the text can't be inserted (e.g., non-editable field), it's automatically copied to your clipboard.

## Troubleshooting

### Hotkey doesn't work
- Verify Accessibility permission is granted (System Settings → Accessibility).
- Check for conflicts with Spotlight, Alfred, Raycast, or other global hotkey apps.
- Try changing the hotkey in Settings → Shortcuts.

### Text doesn't appear in the target app
- Some apps (Slack, VS Code, Terminal) use clipboard-paste fallback. The text should still appear, but your clipboard is briefly used.
- If text never appears, check **Settings → Diagnostics** for the insertion error.
- Ensure the target element is an editable text field.

### "Invalid API key" error
- Re-enter your key in Settings → Providers.
- Click **Test Connection** to verify.
- Ensure you have billing/credits set up with your provider.

### "No microphone found"
- Check that a microphone is connected.
- Check **System Settings → Sound → Input** for the correct device.

### Transcription is slow
- Check your network connection.
- Try `gpt-4o-mini-transcribe` (faster, lower cost) instead of `gpt-4o-transcribe`.
- Check **Settings → Diagnostics** for latency timings.

## Project Structure

```
SPVoice/
├── App/              # App lifecycle, AppDelegate, state coordination
├── UI/               # SwiftUI views (Settings, Overlay, Onboarding, Menu Bar)
├── Services/         # Core services
│   ├── Audio/        # Microphone recording
│   ├── Credentials/  # Keychain storage
│   ├── Diagnostics/  # Logging and debug info
│   ├── History/      # Local dictation history
│   ├── Insertion/    # Focused element detection + text insertion
│   ├── Permissions/  # Permission checks and onboarding
│   ├── Processing/   # Post-transcription text transforms
│   ├── Providers/    # TranscriptionProvider protocol + implementations
│   ├── Shortcut/     # Global hotkey management
│   └── Transcription/ # Provider-agnostic transcription orchestrator
├── Utilities/        # Helpers (Keychain, Pasteboard, CGEvent, Logger)
└── Resources/        # Assets, localization
```

## Architecture

See `docs/architecture.md` for the full system design, including:
- Module responsibilities
- Data flow diagram
- Provider abstraction protocol
- Text insertion strategy chain
- Permissions plan
- Error handling strategy

## Security

- API keys are stored in the macOS Keychain, never in files or logs.
- Audio recordings are temporary files, deleted immediately after transcription.
- No data leaves your machine except API calls to your configured provider.
- No analytics, telemetry, or cloud sync.

## Running Tests

```bash
cd SPVoice
xcodebuild test -project SPVoice.xcodeproj -scheme SPVoice -configuration Debug \
  -destination "platform=macOS"
```

Current baseline: 112 tests passing. Coverage includes app state coordination, transcription service, provider clients (OpenAI, OpenRouter, Gemini), text processing, insertion models, credentials, diagnostics, history, and audio recording.

## Known Limitations

- **OpenRouter and Gemini are experimental.** Audio transcription via chat-completion APIs is less reliable than OpenAI's dedicated speech-to-text endpoint. Accuracy and latency may vary.
- **Gemini inline audio limit** is 20 MB per request. Long recordings may fail.
- **Text insertion** uses Accessibility APIs. Some apps (Electron-based, certain terminals) may only support clipboard-paste fallback.
- **Prompt Mode and Custom Transform** are placeholders — they pass text through without transformation.
- **No App Sandbox** — required for global Accessibility and hotkey access.

## License

[MIT](LICENSE)
