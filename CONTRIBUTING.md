# Contributing to Glass

Thanks for helping improve Glass.

## Before You Start

- Check existing issues before opening a new one.
- Keep pull requests focused. Smaller changes are much easier to review.
- If a change affects the overlay UI or window behavior, include a short note about how you tested it.

## Bug Reports

Please include:

- macOS version
- Glass commit or release version
- What you expected
- What actually happened
- Reproduction steps
- Screenshots or logs if relevant

## Feature Requests

Useful requests usually explain:

- The workflow you are trying to support
- Why the current behavior falls short
- What the new behavior should look like

## Local Development

Requirements:

- macOS 14+
- Xcode command line tools
- Swift 5.10+

Build commands:

```bash
swift build --package-path Glass -c debug
swift build --package-path Glass -c release
./Glass/BuildSupport/build-app.sh
```

Run the installed app with:

```bash
open -a /Applications/Glass.app
```

## Project Areas

- `GlassAppMain.swift`: app lifecycle, overlay windows, multi-display behavior
- `GlassViews.swift`: SwiftUI interface
- `GlassViewModel.swift`: state, transcription flow, copilot orchestration
- `OpenAIServices.swift`: OpenAI clients
- `AudioPipeline.swift`: audio capture and chunking
- `ScreenOCRService.swift`: screenshot and OCR path

## Commit Guidance

- Use short, descriptive commit messages
- Keep unrelated cleanup out of feature commits when possible
- Mention manual verification when the change touches permissions, overlays, or capture behavior

## Code of Conduct

Please follow the repository [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md).
