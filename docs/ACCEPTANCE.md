# Acceptance status

Recorded 2026-09-24. This file distinguishes observed checks from pending live acceptance.

- Native release builds and launches as an installed ad-hoc `.app`.
- 25 Swift tests (including four cancellation boundary cases) and 10 Python tests pass locally. Formatting and tracked-file privacy/attribution checks pass.
- General desktop parser tests cover applications, websites, folders, search, scrolling, controls, volume and safe keys. Safety tests block generic sends, sensitive controls and password/terminal targets. Production launch smoke checks passed for Calculator, TextEdit, Safari and Finder; 98 installed apps were discovered.
- Transcript punctuation revisions remain idempotent; app-name prefixes wait rather than reporting an immediate missing-app error. Failed actions can recover at the next explicit app clause. Ordinary action errors keep speech active rather than reopening Settings and stopping the microphone.
- Real-time paced synthetic file recognition previously returned 17 incremental results, 16 volatile, and a stable app-opening clause before finalization. Four expected command categories parsed. Synthetic “hi” was recognized as “tie”; dictated text is never silently corrected. A later final-build fixture produced nine results, eight volatile. A real speech-to-ActionQueue-to-NSWorkspace test launched Calculator and TextEdit in order, before transcription finalized, without duplicates. Acoustic microphone recognition is checked separately.
- Both pinned checkpoints were measured on MLX CPU/GPU. The selected multilingual/GPU model matches all 48 original reference choices, with probability error below 0.00005. Runtime imports no Torch/Transformers; missing model remains nonfatal for direct commands. No fine-tuning was performed.
- Installed app completed real MLX inference over private stdio with main-loop wake lateness p95 1.23 ms and native RSS 90.3 MB. Model confidence remains unvalidated and therefore abstains.
- macOS retained prior ad-hoc code hashes for Microphone and Accessibility. Repair resets only NotchPilot. A permission-enabled run verified hotkey start, overlay, second-press stop and Escape cancellation. Hold-to-talk had been enabled locally and was restored to the requested toggle mode. The native WhatsApp dry-run passed all four stages: launch, exact contact, draft entry and dry-run Send. A final speech-identity correction changes the unsigned binary and needs renewed approval for its final acoustic check.
- Installed signature verified after real model inference; bundle bytecode writes are disabled. The runtime is installed in Application Support, independent of the source folder.
- Synthetic overlay visually inspected on the physical notch; nonactivating black capsule shows transcript, state and queued actions. Demo sends are mocked.
- No live message test enabled or run. Automated tests never send messages. Generic controls are deliberately not universal application adapters.
- External-display geometry and denied-permission handling are unit-tested. Physical external-display, fullscreen and multi-Space checks remain unverified.
- CI passed for commit 6661ee1, run 35971731613; later changes require their own post-push CI check.

Do not describe the project as complete while applicable live gates remain pending.

Reproduce the real progressive launch check with `./scripts/test-speech.sh`. Add `--microphone` for a synthetic acoustic loop through speakers and the approved microphone. Both modes restrict execution to Calculator and TextEdit; they cannot type or send messages.
