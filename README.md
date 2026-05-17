# Glass

Glass is a native Swift macOS overlay assistant for live meetings.

The current app is focused on a transparent floating overlay, live transcription, screen-context OCR, and quick copilot responses without the previous Electron stack.

## What Glass Does

- Native SwiftUI/AppKit overlay UI
- Always-on-top overlay across Spaces and displays
- Overlay hidden from normal screenshots and screen-sharing capture
- Live microphone capture
- System-audio and OCR hooks for meeting context
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
- `⌃⌥⌘R`: generate an AI response from the meeting context collected so far
- `⌃⌥⌘F`: start or stop meeting context collection
- `⌃⌥⌘W`: move Glass up
- `⌃⌥⌘A`: move Glass left
- `⌃⌥⌘S`: move Glass down
- `⌃⌥⌘D`: move Glass right
- `Settings → Request Screen Access`: ask macOS for Screen Recording permission
- `Settings → Relaunch Glass`: restart the app after granting Screen Recording so the permission takes effect

Glass keeps collecting transcript and screen context continuously during a meeting, but it only calls OpenAI for a reply when you explicitly press `⌃⌥⌘R` or click `Ask AI`.

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

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## Security

See [SECURITY.md](./SECURITY.md).

## License

This repository remains licensed under [AGPL-3.0](./LICENSE).

## Status

Glass is actively being rebuilt as a standalone native macOS app. Expect rapid iteration.
