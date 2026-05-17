# Privacy

## Summary

Glass is currently a local-first macOS application.

## What Glass Stores

- Your OpenAI API key is stored in the macOS Keychain.
- Current-session UI state, transcript drafts, and copilot context are kept in local app memory while Glass is running.

## What Glass Sends Off Device

When you use OpenAI-backed features, Glass may send:

- audio chunks for transcription
- prompt text for copilot responses
- screenshot-derived OCR context when you explicitly use screen-context features

Those requests go to the configured OpenAI endpoint.

## What Glass Does Not Currently Include

- No built-in cloud account system
- No bundled analytics or telemetry service in the native Swift app
- No server-side meeting-history sync in the current standalone repo

## Local Control

You control local app removal.

- Removing `/Applications/Glass.app` removes the installed app bundle.
- Keychain entries can be removed through Keychain Access if you want to clear saved credentials.

## Open Source

This repository is public, so you can inspect the current implementation directly.
