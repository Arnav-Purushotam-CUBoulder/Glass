# Security Policy

## Supported Versions

Security fixes are currently applied to:

- the latest commit on `main`
- the latest tagged release, when releases exist

Older snapshots may not receive fixes.

## Reporting

Please avoid posting exploit details in a public issue.

Preferred path:

1. Use GitHub's private security reporting for this repository if it is enabled.
2. If private reporting is not available, open a minimal public issue titled `Security contact requested` without technical details, and we will move the conversation to a safer channel.

## In Scope

- Overlay visibility and screen-capture protections
- Microphone and screen-permission handling
- Keychain storage and credential handling
- OpenAI request handling
- Unsafe local file access
- Crashes or logic flaws that expose sensitive user data

## Out of Scope

- Pure model hallucinations
- Generic upstream provider outages
- Issues that require full prior access to the user's unlocked machine
- Feature requests or non-security bugs

## Response Goals

- Acknowledge reports as quickly as practical
- Reproduce confirmed issues
- Patch high-impact issues first
- Credit reporters when appropriate and wanted

## Notes

This project does not currently run a paid bug-bounty program.
