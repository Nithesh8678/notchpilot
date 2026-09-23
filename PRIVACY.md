# Privacy

No microphone audio, transcripts, contacts, messages, screen contents, or model requests are uploaded. There is no telemetry, analytics SDK, automatic crash upload, audio recording, or cloud AI fallback. Screen Recording and Automation permissions are not requested.

Apple downloads speech language assets during setup; recognition uses SpeechAnalyzer and SpeechTranscriber locally. Setup downloads dependencies from package registries and model weights from Hugging Face. These are inbound setup requests and contain no spoken data. Laya inference is forced offline.

Transcripts remain in memory and are cleared after the locally configured 5–120 second retention window, default 30 seconds after cancellation. The microphone stops immediately when a session is cancelled or reaches its 60-second timeout. Messages typed into WhatsApp become drafts in WhatsApp; that application's own storage and sync policies apply. Dry Run never presses Send, but does enter a draft.

Local preferences contain shortcut, language, mode, and aliases. The privacy-safe action audit stores at most 200 timestamps, action types, target application category, success/failure, and elapsed time. It contains no free-form command, recipient, message, audio, or snapshot. Delete it in Settings → Diagnostics.

Local runtime files and model weights live under `~/Library/Application Support/NotchPilot`. Source, tests and example media contain only synthetic data. Deleting the app does not remove these local files or its UserDefaults preferences; remove them yourself if uninstalling completely.
