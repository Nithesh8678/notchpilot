# Contributing

Use macOS 26, Xcode 26 or later, Python 3.11+ and the GitHub CLI. Run `./scripts/bootstrap.sh --skip-model`, `./scripts/test.sh`, and `./scripts/lint.sh`. `swift format format --in-place --recursive Sources Tests Package.swift` formats Swift sources.

Keep UI, speech, decisions, and execution separate. Every adapter must support bounded searches, exact target verification, cancellation before mutations, safe timeouts, and mock tests. Never add screen coordinates to production execution. Do not introduce network inference or telemetry.

Use synthetic fixtures and Dry Run. Do not attach real conversations, contacts, audio, screenshots of private content, or local runtime configuration to issues. Propose adapter changes with sanitized structural descriptions and reproducible steps. Small focused pull requests are welcome. Submissions are under Apache-2.0.
