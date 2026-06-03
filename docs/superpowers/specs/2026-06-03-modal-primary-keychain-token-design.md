# Modal Primary Backend and Keychain Token Persistence Design

## Goal

Make the macOS prototype use Modal as its primary remote backend without asking
the user to re-enter the WebSocket URL and bearer token on every launch.

## Scope

This is a macOS-first prototype convenience slice. It does not change the
backend WebSocket contract, Modal deployment shape, ASR model settings, or iOS
home-screen flow.

The Modal URL is not treated as a secret. The bearer token is treated as a
secret and must not be committed, written to `UserDefaults`, printed in docs, or
baked into Swift source.

## User Experience

On first launch after the change, the macOS app should already point at the
Modal WebSocket endpoint:

```text
wss://moabdelmoez--tarteel-realtime-asr-fastapi-app.modal.run/ws/recitation
```

The app should select:

```text
Backend: Custom
Provider: Modal
```

The user enters the Modal bearer token once in Settings. After that, the token
is loaded from macOS Keychain on future launches. Editing or clearing the token
in Settings updates Keychain.

If the user changes backend/provider/URL after this change, those non-secret
preferences continue to persist through the existing preferences store behavior.

## Architecture

Keep transport unchanged: `BackendWebSocketClient` still receives an optional
authorization token and sends it as:

```http
Authorization: Bearer <token>
```

Add a small token-storage boundary in `TarteelClientCore`, for example:

```swift
public protocol BackendBearerTokenStoring {
    func token(for provider: BackendProvider) -> String
    func setToken(_ token: String, for provider: BackendProvider)
}
```

The shared `RecitationViewModel` owns the token field state and calls this
storage boundary when:

- initializing from stored preferences
- switching custom providers
- editing the token text

Use a no-op or in-memory implementation as the default for tests and non-macOS
contexts. The macOS app injects a Keychain implementation.

## macOS Defaults

Do not globally change `UserDefaultsRecitationPreferencesStore` defaults to
Modal. The shared default should remain friendly to local simulator development.

Instead, add configurable defaults to the preferences store or construct a
macOS-specific preferences store in `TarteelPrototypeMacApp` with:

```text
backendPreset: custom
customBackendProvider: modal
customBackendURLText: wss://moabdelmoez--tarteel-realtime-asr-fastapi-app.modal.run/ws/recitation
```

Persisted user choices still win over defaults. This avoids overwriting a user
who already selected another backend.

## Keychain Behavior

The Keychain item should be scoped to the macOS app and provider. A practical
shape is:

```text
service: dev.mostafa.TarteelPrototypeMac.backend-token
account: modal
```

Provider-specific accounts keep future `Generic`, `RunPod`, and `Modal` tokens
separate. Clearing the Settings field deletes the provider token from Keychain.

The UI should update the token help text for Modal from memory-only language to
secure persistence language on macOS. The iPhone settings copy remains
memory-only for this slice because this request is macOS-focused.

## Error Handling

If Keychain read fails, start with an empty token and let the user paste it
again. If Keychain write/delete fails, keep the typed token in memory for the
current app process and surface a short Settings error message so the user knows
the token may not survive restart.

Do not expose the token in event history, diagnostics, drag-out text, logs, or
test output.

## Testing

Use TDD in the shared Swift package first:

- preferences defaults can be configured for macOS without changing generic
  defaults
- token storage is not part of `UserDefaultsRecitationPreferencesStore`
- `RecitationViewModel` loads a stored Modal token on launch
- switching providers loads the provider-specific stored token
- clearing the token calls the storage delete path
- recording still sends the bearer token through the existing socket boundary

Use source guardrail tests for the macOS target:

- macOS app injects Modal defaults
- macOS app injects a Keychain token store
- Settings copy no longer claims Modal token is memory-only on macOS

Then run the existing Swift client core tests and macOS app build.

## Non-Goals

- Do not store the bearer token in `UserDefaults`.
- Do not commit the bearer token.
- Do not add a new transport.
- Do not make Modal the default for the iPhone simulator flow.
- Do not claim Modal ASR quality is fully proven without a fresh replay probe.

## Acceptance Criteria

- A clean macOS launch defaults to Custom plus Modal plus the Modal WSS URL.
- After entering a Modal token once, quitting and reopening the macOS app keeps
  the token available for the next recording.
- The persisted token is in Keychain, not `UserDefaults`.
- Existing iPhone/local simulator defaults stay intact.
- Relevant Swift package tests, macOS source guardrails, and macOS build pass.
