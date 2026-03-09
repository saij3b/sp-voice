# Provider Abstraction Design

## Core Protocol

All transcription providers conform to a single `TranscriptionProvider` protocol. This is the only interface that `TranscriptionService` knows about — it never touches provider-specific types directly.

```swift
// MARK: - Provider Protocol

protocol TranscriptionProvider {
    var id: ProviderID { get }
    var displayName: String { get }
    var supportedModels: [TranscriptionModel] { get }
    var defaultModel: TranscriptionModel { get }

    /// Check that the stored API key is valid and the provider is reachable.
    func validateCredentials() async throws

    /// Transcribe audio. Returns a normalized result regardless of provider.
    func transcribe(
        audioURL: URL,
        model: TranscriptionModel?,
        options: TranscriptionOptions?
    ) async throws -> TranscriptionResult
}
```

## Shared Types

```swift
enum ProviderID: String, Codable, CaseIterable {
    case openai
    case openrouter
    case gemini
}

struct TranscriptionModel: Identifiable, Codable, Hashable {
    let id: String              // e.g. "gpt-4o-transcribe"
    let displayName: String     // e.g. "GPT-4o Transcribe"
    let provider: ProviderID
}

struct TranscriptionOptions {
    var language: String?       // ISO 639-1 code, e.g. "en"
    var prompt: String?         // vocabulary hints / proper nouns
    var temperature: Double?    // 0.0–1.0
}

struct TranscriptionResult {
    let text: String
    let provider: ProviderID
    let model: String
    let language: String?
    let latencyMs: Int
    let rawMetadata: [String: Any]?
}
```

## Provider Error Types

```swift
enum ProviderError: Error, LocalizedError {
    case invalidCredentials
    case networkUnavailable
    case rateLimited(retryAfterSeconds: Int?)
    case serverError(statusCode: Int, message: String?)
    case timeout
    case unsupportedAudioFormat
    case fileTooLarge(maxMB: Int)
    case transcriptionEmpty
    case unknown(underlying: Error)
}
```

---

## OpenAI Provider

### API Contract
- **Endpoint**: `POST https://api.openai.com/v1/audio/transcriptions`
- **Auth**: `Authorization: Bearer {apiKey}`
- **Content-Type**: `multipart/form-data`
- **Required fields**: `file` (audio binary), `model` (string)
- **Optional fields**: `language`, `prompt`, `response_format` (always "json"), `temperature`
- **Response (JSON)**: `{ "text": "transcribed text" }`

### Models
- `gpt-4o-transcribe` — highest accuracy, default
- `gpt-4o-mini-transcribe` — lower cost, slightly lower accuracy

### Audio Requirements
- Formats: mp3, mp4, mpeg, mpga, m4a, wav, webm
- Max file size: 25 MB
- Recommended: m4a at 16 kHz mono (small files, fast upload)

### Validation
- `GET https://api.openai.com/v1/models` with bearer token
- 200 → key is valid
- 401 → invalid key
- Key format hint: starts with `sk-`

### Request Construction (pseudocode)
```
var request = URLRequest(url: transcriptionsURL)
request.httpMethod = "POST"
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

let boundary = UUID().uuidString
request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

body = multipart {
    field("model", model.id)
    field("response_format", "json")
    if let language { field("language", language) }
    if let prompt { field("prompt", prompt) }
    file("file", audioData, filename: "audio.m4a", mimeType: "audio/m4a")
}
```

---

## OpenRouter Provider

### API Contract
- **Endpoint**: `POST https://openrouter.ai/api/v1/chat/completions`
- **Auth**: `Authorization: Bearer {apiKey}`
- **Content-Type**: `application/json`
- **Body**: OpenAI-compatible chat completions with `input_audio` content type

### Request Shape
```json
{
  "model": "openai/gpt-4o-audio-preview",
  "messages": [
    {
      "role": "system",
      "content": "You are a precise speech transcription assistant. Transcribe the following audio exactly as spoken. Output only the transcription text, nothing else."
    },
    {
      "role": "user",
      "content": [
        {
          "type": "input_audio",
          "input_audio": {
            "data": "<base64-encoded-audio>",
            "format": "wav"
          }
        }
      ]
    }
  ]
}
```

### Response
```json
{
  "choices": [
    {
      "message": {
        "content": "transcribed text here"
      }
    }
  ]
}
```

### Key Differences from OpenAI Provider
1. **No dedicated transcription endpoint** — uses chat completions with audio input.
2. **Audio must be base64-encoded** inline in the request body (not multipart file upload).
3. **Transcription quality depends on the system prompt** — the provider implementation must craft a reliable instruction.
4. **Model availability varies** — not all OpenRouter models support audio input. The provider should filter `supportedModels` to audio-capable models.

### Audio Encoding
- Audio file must be read as bytes, then base64-encoded.
- Format string must match the actual codec: "wav", "mp3", "m4a", etc.
- File size limit depends on the underlying model; generally safe up to 20 MB.

### Validation
- `GET https://openrouter.ai/api/v1/models` — 200 = valid key
- Key format: typically `sk-or-...`

### Available Audio Models (as of early 2026)
- `openai/gpt-4o-audio-preview` — OpenAI's audio model via OpenRouter
- Additional models may support audio input; filter by `input_modalities` containing "audio" on the models list endpoint.

---

## Gemini Provider

### API Contract
- **Endpoint**: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- **Auth**: `?key={apiKey}` query parameter
- **Content-Type**: `application/json`

### Request Shape
```json
{
  "contents": [
    {
      "parts": [
        {
          "text": "Transcribe this audio exactly as spoken. Return only the transcription text, with no commentary or formatting."
        },
        {
          "inlineData": {
            "mimeType": "audio/wav",
            "data": "<base64-encoded-audio>"
          }
        }
      ]
    }
  ]
}
```

### Response
```json
{
  "candidates": [
    {
      "content": {
        "parts": [
          {
            "text": "transcribed text here"
          }
        ]
      }
    }
  ]
}
```

### Models
- `gemini-2.5-flash` — fast, cost-effective, good for short dictation
- `gemini-2.5-pro` — higher accuracy, better for noisy audio or technical vocabulary

### Audio Requirements
- Formats: WAV, MP3, AIFF, AAC, OGG, FLAC
- Max inline size: 20 MB (use Files API for larger, but dictation clips should always be under this)
- Gemini downsamples to 16 Kbps internally
- Multi-channel audio is combined into mono

### Key Differences
1. **Prompt-driven transcription** — there is no dedicated STT endpoint. Gemini treats audio as a multimodal input and follows the text instruction.
2. **Quality depends heavily on the prompt** — the provider must use a carefully crafted instruction to get faithful transcription without embellishment.
3. **API key is passed as a query parameter**, not a header.
4. **No `prompt` or `temperature` fields for transcription** — these concepts map to the text instruction and `generationConfig.temperature` respectively.

### Validation
- Send a trivial `generateContent` request with a text-only prompt (e.g., "Say hello")
- 200 with valid response → key is valid
- 400/403 → invalid key or API not enabled

---

## Provider Manager Logic

### Auto-Default Selection
```
if only one provider has a stored key → that provider is primary
if multiple providers have keys → user must explicitly choose primary in Settings
if no providers have keys → show "Add a provider" prompt
```

### Fallback Chain
```
1. Try primary provider
2. If primary fails with retryable error (429, 500+, timeout):
   a. If secondary provider is configured → try secondary
   b. Else → report failure
3. If primary fails with non-retryable error (401, unsupported format):
   → Report failure immediately (don't waste the fallback on a config error)
```

### Model Selection Per Provider
- Each provider stores a `selectedModelId` in UserDefaults
- Default: provider's `defaultModel`
- User can override in Settings → Providers → {Provider} → Model

---

## Adding a New Provider

To add a new transcription provider:

1. Create `NewProvider.swift` in `Services/Providers/`
2. Conform to `TranscriptionProvider`
3. Implement `validateCredentials()` and `transcribe(audioURL:model:options:)`
4. Add a case to `ProviderID` enum
5. Register in `ProviderManager.availableProviders`
6. Add UI for key entry in `ProvidersSettingsView`
7. Add Keychain account constant in `CredentialsStore`

No other modules need to change — `TranscriptionService`, `TextInsertionService`, and the rest of the pipeline are provider-agnostic.
