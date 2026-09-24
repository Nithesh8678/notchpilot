# v0.1.0 source release preparation

The application bundle declares version 0.1.0. The repository has independent Git history, an Apache-2.0 license, Laya attribution and pinned model provenance. The local app is ad-hoc signed; this is a source release, with no signed or notarized binary.

Verified on the development Mac:

- Release build and 25 Swift plus 10 Python tests passed.
- Formatting, privacy audit, code signature and public-repository CI passed.
- Option + Space in toggle mode displayed incremental speech and launched Calculator from the user's spoken command.
- Synthetic progressive speech launched Calculator and TextEdit in order before the utterance ended.
- The WhatsApp adapter completed a prior exact-conversation Dry Run without a real send; it always requires the intended app to be frontmost before typing.
- MLX model parity, resource use and native dispatch measurements are recorded in `PERFORMANCE.md`.

Before marking the release fully accepted, verify the updated app's macOS Microphone and Accessibility approvals and rerun the WhatsApp Dry Run with the final focus check on the development Mac. A user-enabled live message test remains outside automated acceptance. Hardware-specific external-display behavior is covered by layout tests but needs a physical display check when one is available.

The supported command scope and current limits are in the README. No claim of universal application control or validated model-based decisions is made.
