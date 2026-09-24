# Acceptance status

Recorded 2026-09-24. This file distinguishes observed checks from pending live acceptance.

- Native release builds and launches as an installed ad-hoc `.app`.
- 24 Swift tests (including four cancellation boundary cases) and 10 Python tests pass locally. Formatting and tracked-file privacy/attribution checks pass.
- General desktop parser tests cover applications, websites, folders, search, scrolling, controls, volume and safe keys. Safety tests block generic sends, sensitive controls and password/terminal targets. Production launch smoke checks passed for Calculator, TextEdit, Safari and Finder; 98 installed apps were discovered.
- Transcript punctuation revisions remain idempotent; app-name prefixes wait rather than reporting an immediate missing-app error. Failed actions can recover at the next explicit app clause. Ordinary action errors keep speech active rather than reopening Settings and stopping the microphone.
- Real-time paced synthetic file recognition previously returned 17 incremental results, 16 volatile, and a stable app-opening clause before finalization. Four expected command categories parsed. Synthetic “hi” was recognized as “tie”; dictated text is never silently corrected. Live microphone recognition remains pending permission-enabled verification.
- Both pinned checkpoints were measured on MLX CPU/GPU. The selected multilingual/GPU model matches all 48 original reference choices, with probability error below 0.00005. Runtime imports no Torch/Transformers; missing model remains nonfatal for direct commands. No fine-tuning was performed.
- Installed app completed real MLX inference over private stdio with main-loop wake lateness p95 1.23 ms and native RSS 90.3 MB. Model confidence remains unvalidated and therefore abstains.
- macOS retained prior ad-hoc code hashes for Microphone and Accessibility. Repair resets only NotchPilot. The final installed binary requires renewed approval. Global hotkey, live speech, native WhatsApp dry-run and cancellation during live adapter stages are still pending verified permission-enabled runs.
- Installed signature verified after real model inference; bundle bytecode writes are disabled. The runtime is installed in Application Support, independent of the source folder.
- Synthetic overlay visually inspected on the physical notch; nonactivating black capsule shows transcript, state and queued actions. Demo sends are mocked.
- No live message test enabled or run. Automated tests never send messages. Generic controls are deliberately not universal application adapters.
- External-display geometry and denied-permission handling are unit-tested. Physical external-display, fullscreen and multi-Space checks remain unverified.
- CI results for this revision are checked after push; the latest linked run is available on the repository Actions tab.

Do not describe the project as complete while applicable live gates remain pending.
