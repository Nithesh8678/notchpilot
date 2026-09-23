# Permissions and onboarding

Launch the built app. Setup explains each requested permission and provides the relevant button.

1. **Microphone:** click Allow Microphone and approve the macOS prompt. Capture runs only during a listening session. No audio is stored.
2. **Accessibility:** click Open Accessibility Settings, enable NotchPilot under Privacy & Security → Accessibility, then refresh permission status. macOS may request your password or Touch ID. Only you should approve that step.
3. **Local speech assets:** choose a supported language identifier, then Install / Prepare Speech Assets. Apple may download the language pack. SpeechAnalyzer recognition is on-device and does not require a remote recognition fallback.

This version does not request Screen Recording, Automation, Documents access, or Full Disk Access. The installed Python runtime and model weights reside in Application Support. Speech recognition authorization is not requested because the selected on-device SpeechAnalyzer API does not use the legacy SFSpeechRecognizer authorization path.

Denied or revoked microphone access returns to onboarding. Denied Accessibility prevents control and shows the settings route rather than crashing. Direct app launching does not itself need Accessibility; the WhatsApp workflow does.

Ad-hoc development builds can require permissions to be granted again after rebuilding or moving the app. An older build may appear under its renamed location. Add the current `.app` using the + button if needed. Rebuilds are not signed with an Apple Developer identity and are not notarized.

Use the microphone indicator in macOS to confirm capture stops after Escape or a second hotkey press. Sessions also stop after 60 seconds. Close Settings to return to the menu-bar-only experience.
