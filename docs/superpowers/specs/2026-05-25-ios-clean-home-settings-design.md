# iOS Clean Home Settings Design

## Goal

Modernize the SwiftUI prototype home screen so it reads as a clean recitation surface instead of a technical control panel.

## User-Facing Behavior

- The home screen uses a white background with dark, readable text and teal accents.
- The home screen keeps only recitation-facing controls and state:
  - status and ayah information
  - Auto/Surah selection
  - Surah picker when Surah mode is active
  - voice activity indicator
  - microphone button
- A gear button opens settings.
- Settings contains only technical backend controls:
  - backend preset
  - custom WebSocket URL
  - RunPod API key
- Recording disables settings controls that would change the active connection.

## Architecture

Keep the existing `RecitationViewModel` state and WebSocket behavior unchanged. This slice is a SwiftUI composition and styling change in `ContentView.swift`, with source-guard tests updated to assert the new control placement.

## Components

- `ContentView`: white home screen, top gear button, status panel, recitation controls, message, voice indicator, mic button.
- `SettingsSheet`: backend preset picker, backend URL text field, RunPod API key secure field.
- `DebugStatusPanel`: restyled for a light background while preserving the same fields.
- `VoiceActivityIndicator`: restyled for teal/neutral colors on white.

## Testing

- Update iOS source guardrails to ensure backend controls live in settings and recitation controls remain on the home screen.
- Run focused iOS source tests.
- Run Swift client core tests because recitation scope and endpoint behavior are still part of the affected workflow.
- Run the iOS app build.
