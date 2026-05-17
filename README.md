# Glass

Glass is a native Swift macOS overlay assistant for live meetings.

The current app is focused on a transparent floating overlay, live transcription, screen-context OCR, and quick copilot responses without the previous Electron stack.

## What Glass Does

- Native SwiftUI/AppKit overlay UI
- Always-on-top overlay across Spaces and displays
- Overlay hidden from normal screenshots and screen-sharing capture
- Live microphone capture
- System-audio and OCR hooks for meeting context
- AirPods and other Bluetooth headset compatibility through the active macOS input/output devices
- OpenAI-powered transcription and response generation
- Rolling conversation context with "what to say next" help
- Local OpenAI key storage in macOS Keychain

## Project Layout

- `Glass/Package.swift`: Swift package entry
- `Glass/Sources/Glass/GlassAppMain.swift`: app lifecycle and window management
- `Glass/Sources/Glass/GlassViews.swift`: overlay UI
- `Glass/Sources/Glass/GlassViewModel.swift`: session state and copilot flow
- `Glass/Sources/Glass/OpenAIServices.swift`: OpenAI transcription and response clients
- `Glass/Sources/Glass/AudioPipeline.swift`: audio capture pipeline
- `Glass/Sources/Glass/ScreenOCRService.swift`: OCR and screen-context analysis
- `Glass/BuildSupport/build-app.sh`: local app-bundle build script

## Build

Requirements:

- macOS 14+
- Xcode command line tools
- Swift 5.10+

Commands:

```bash
swift build --package-path Glass -c release
./Glass/BuildSupport/build-app.sh
```

The packaged app bundle is created at:

```text
Glass/build/Glass.app
```

## Install Locally

```bash
rm -rf /Applications/Glass.app
cp -R Glass/build/Glass.app /Applications/Glass.app
open -a /Applications/Glass.app
```

## Controls

- `⌃⌥⌘E`: open Glass on the currently active screen/space and collect context for that screen
- `⌃⌥⌘Q`: hide Glass from the current screen/space without quitting the app
- `⌃⌥⌘R`: generate a Python answer from the meeting context collected so far
- `⌃⌥⌘C`: generate a C++ answer from the meeting context collected so far
- `⌃⌥⌘F`: start or stop meeting context collection
- `⌃⌥⌘W`: move Glass up
- `⌃⌥⌘A`: move Glass left
- `⌃⌥⌘S`: move Glass down
- `⌃⌥⌘D`: move Glass right
- `⌃⌥⌘↑`: scroll up through the AI chat history
- `⌃⌥⌘↓`: scroll down through the AI chat history
- `Settings → Request Screen Access`: ask macOS for Screen Recording permission
- `Settings → Relaunch Glass`: restart the app after granting Screen Recording so the permission takes effect

Glass keeps collecting transcript and screen context continuously during a meeting, but it only calls OpenAI for a reply when you explicitly press `⌃⌥⌘R`, `⌃⌥⌘C`, or click `Ask AI`. For coding and DSA prompts, the reply now includes a concise explanation plus Python or C++ code with a comment line directly above each code line when the model has enough context.

If your Mac input is set to AirPods, Glass will use the AirPods microphone for the `You` channel. If meeting audio is playing through AirPods, Glass still captures that laptop/system audio separately for the `Meeting` channel. During a live meeting, Glass now also rebinds the microphone path when the active input device changes.

## Permissions

Glass may ask for:

- Microphone access for live transcription
- Screen Recording access for OCR and future system-audio capture

Because the overlay is intentionally excluded from screen capture, some automation tools may show a blank preview even while the UI is visible on the desktop.

## Privacy Notes

- The current app stores the OpenAI API key in macOS Keychain.
- Live transcript state is kept locally in app memory during the running session.
- When you use OpenAI-backed features, the relevant audio or prompt data is sent to OpenAI.

See [PRIVACY.md](./PRIVACY.md) for the current repo policy.

## Status

Glass is actively being rebuilt as a standalone native macOS app. Expect rapid iteration.
