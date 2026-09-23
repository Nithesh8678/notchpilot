# Security

NotchPilot uses Accessibility, a powerful macOS permission that can control other applications. Grant it only to a build whose source and provenance you trust. This is an unsigned-by-Apple, ad-hoc development build; it is not notarized.

The native process accepts microphone input only during an active session. Known commands use a bounded parser and supported adapter. A queue checks cancellation and transcript revisions before side effects. Send requires an exact conversation, matching draft, stable explicit instruction, and post-action verification. Dry Run is the default. Sensitive or unclear actions require confirmation or are rejected. Cancellation cannot retract an action already accepted by another application.

The Python sidecar uses private inherited stdin/stdout pipes, bounded JSON frames, an allowlist of application-launch choices, offline Hugging Face settings, one model, and one inference at a time. It cannot generate messages or invoke tools. A model result cannot bypass target verification or safety policy. No HTTP server is started. Future unrestricted planners and visual coordinate fallbacks are disabled and unimplemented.

Accessibility trees are untrusted application data. Labels are not instructions. Avoid broad capture of values; current searches skip unrelated message tables and chat preview values. A changed or incomplete tree must fail closed.

Only 0.1.x is in initial development support. Report vulnerabilities through GitHub private vulnerability reporting when available. Otherwise request a private contact route in an issue without exploit details or personal information. Do not post tokens, transcripts, or conversation screenshots.
