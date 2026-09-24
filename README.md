# NotchPilot

Native, local voice control from the MacBook notch area. An independent macOS 26 project using selected, modified Laya components under Apache-2.0. Not affiliated with Laya, Convai Innovations, or Apple.

![Synthetic interface illustration](docs/assets/notchpilot-demo.svg)

Version **0.1.0** is being verified. Do not treat the current acceptance status as a completed release until the checks in `docs/ACCEPTANCE.md` are filled in.

## Setup

Requires Apple Silicon, macOS 26, Xcode 26+ (including accepted license), Python 3.11+, Git and GitHub CLI. No Xcode project needs to be opened.

```bash
./scripts/bootstrap.sh
./scripts/run.sh
```

Setup creates a development `.venv`, installs a separate pinned MLX runtime in Application Support, downloads one optional Laya checkpoint there, and installs a local `.app` in `~/Applications/NotchPilot.app`. Approve **Microphone** and **Accessibility** in Setup, then prepare the local speech assets. Screen Recording is not needed. `./scripts/bootstrap.sh --skip-model` builds deterministic control without model downloads.

Press **Option + Space** to listen. Press it again, or **Escape**, to cancel and stop the microphone. The shortcut is configurable. Hold-to-talk is optional. Each session has a 60-second limit.

Say:

- “Open Safari, then new tab.”
- “Open Calculator.” or “Open Visual Studio Code.”
- “Open Downloads.” or “Visit example.com.”
- “Set volume to 30.” or “Mute.”
- In an active app: “Scroll down”, “Click Back”, or “Search for apples”.
- With an empty text field focused: “Type your exact words”.
- “Open WhatsApp, go to Mummy, type hi and send.”
- “Open WhatsApp, go to Mummy, type hi.” — leaves a draft.

**Dry Run is on by default.** It opens the exact conversation and enters the draft, but does not send. Map a spoken alias to an exact display name in Settings. An ambiguous recipient is rejected. In live mode, Send requires an explicit trailing instruction in the recognizer's committed text. Sensitive messages require confirmation. Cancellation cannot retract a message already handed to WhatsApp.

## Supported scope

Launch/focus installed apps by their exact names in the standard Applications folders, including Finder and Safari. Open website addresses and named folders or exact file paths. Control system volume/mute. In apps exposing suitable Accessibility controls, enter text into an empty focused field, fill Search, press an exact uniquely named button or menu item, scroll, use safe navigation/editing shortcuts, and minimize/zoom windows. Playback controls require an accessible Play/Pause/Next/Previous button in the active app.

The verified messaging workflow is specific to native WhatsApp for macOS. Generic controls cannot send messages or commit sensitive operations. They refuse ambiguous controls, password fields, terminals, password managers and security settings. Generic clicks, scrolling and keyboard shortcuts report dispatch; only dedicated adapters can verify application-specific outcomes. Dry Run prevents messaging sends; it does **not** suppress ordinary app launches, typing, clicks or volume changes.

This is not universal control of every app. English command grammar is required; arbitrary requests, deletion, purchases, financial activity, public posting and unrestricted plans are unsupported. Dictated text remains verbatim, including recognition punctuation; after “type”, only a trailing “and send” is interpreted as another action. Third-party UI changes can require adapter updates. Missing Accessibility semantics produce a useful error, never guessed coordinates. An action error leaves listening active so a new explicit “then open …” clause can recover; Escape always cancels.

## Local by design

No audio retention, transcript uploads, telemetry or automatic crash uploads. Transcripts expire from memory. Aliases stay in local preferences. Diagnostics record action categories and timings, never recipients or messages. Laya uses one offline checkpoint through a native MLX inference port and private pipes; deterministic commands do not wait for it. Its current fallback abstains because the small synthetic validation set did not meet the confidence gate. See [privacy](PRIVACY.md), [security](SECURITY.md), and [model evaluation](docs/MODELS.md).

## Development

```bash
./scripts/build.sh       # release .app; build/NotchPilot.app points to it
./scripts/test.sh        # native and Python tests; no real messages
./scripts/lint.sh        # formatting and repository checks
./scripts/benchmark.sh   # sequential local MLX CPU/GPU benchmarks and native harness
./scripts/package.sh     # verified ad-hoc local ZIP; not notarized
```

Native builds are staged outside synced Documents folders to avoid Finder metadata interfering with code signing. After setup, the Finder-launchable app is installed in `~/Applications/NotchPilot.app` and linked from `build/NotchPilot.app`. The installed Python runtime is independent of the checkout, so the sidecar does not need access to Documents or Desktop. Keep the Homebrew/system Python used during setup installed; rerun bootstrap after replacing it. See [permissions](docs/PERMISSIONS.md) for development-build permission resets.

[Architecture](docs/ARCHITECTURE.md) · [Performance](docs/PERFORMANCE.md) · [Adding an adapter](docs/ADDING_AN_APP_ADAPTER.md) · [Contributing](CONTRIBUTING.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)

## Roadmap

- Broader sanitized WhatsApp-version fixtures and localization coverage.
- More supported application adapters with verified APIs and tests.
- Independently labeled data and held-out validation before enabling optional model decisions.
- Reproducible signed/notarized distribution when a maintainer authorizes Apple Developer credentials.

No roadmap item is a claim of current support.
