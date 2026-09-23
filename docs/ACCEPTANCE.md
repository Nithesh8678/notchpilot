# Acceptance status

This file records observed results rather than assuming that a successful build proves live control.

- Native app compiles and launches as a real ad-hoc `.app`.
- 20 Swift tests (including four action-boundary cancellation cases) and 8 Python tests pass locally.
- Formatting and tracked-file privacy/attribution checks pass.
- Real-time paced synthetic file recognition returned 17 incremental results, 16 volatile, and recognized a stable app-opening clause before finalization. It parsed the four expected command categories. The synthetic voice’s “hi” was recognized as “tie”; dictated text is not silently corrected. Live microphone recognition is not yet verified.
- CPU/MPS benchmarks for both checkpoints completed; the offline sidecar returned a gated abstention through its real private stdio protocol.
- Microphone is approved for the installed app and on-device assets are ready. Accessibility remains denied: macOS reports a stale signing requirement even after toggling the entry. Re-adding the installed app is pending user approval.
- Global hotkey, microphone capture, native WhatsApp dry-run, cancellation during each live stage, remain pending final permission-enabled verification. After relocating the installed Python runtime into Application Support, the installed app completed real sidecar inference with main-loop wake lateness p95 1.24 ms. The earlier model-unavailable result was traced to source-folder access.
- The installed app’s code signature remains valid after real model inference; Python bytecode writes inside the sealed bundle are disabled.
- The synthetic in-app demo displays a nonactivating black overlay with state, action, and queued-action labels. Its draft/send operations are mocked.
- A live message test has not been enabled or run. Automated tests cannot send real messages.
- External-display geometry and permission-denial logic are unit-tested; physical external display and fullscreen/multi-Space checks are not yet verified.
- Public repository CI passed through commit 97f36c1 (run 35867288443), including the signed-bundle fix. Later test changes require their own CI verification.

The project must not be described as complete while applicable gates remain pending.
