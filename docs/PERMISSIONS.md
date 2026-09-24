# Permissions and onboarding

Launch the built app. Setup explains each requested permission and provides the relevant button.

1. **Microphone:** click Allow Microphone and approve the macOS prompt. Capture runs only during a listening session. No audio is stored.
2. **Accessibility:** click Open Accessibility Settings, enable NotchPilot under Privacy & Security → Accessibility, then refresh permission status. macOS may request your password or Touch ID. Only you should approve that step.
3. **Local speech assets:** choose a supported language identifier, then Install / Prepare Speech Assets. Apple may download the language pack. SpeechAnalyzer recognition is on-device and does not require a remote recognition fallback.

This version does not request Screen Recording, Automation, Documents access, or Full Disk Access. The installed Python runtime and model weights reside in Application Support. Speech recognition authorization is not requested because the selected on-device SpeechAnalyzer API does not use the legacy SFSpeechRecognizer authorization path.

Denied or revoked microphone access returns to onboarding. Denied Accessibility prevents AX control and offers the settings route rather than crashing or repeatedly interrupting speech. Opening apps and changing system volume do not require Accessibility. Direct app launching does not itself need Accessibility; the WhatsApp workflow does.

Ad-hoc development builds can require permissions again after a rebuild. macOS can retain an old code-signing hash even while its switch is on. If Setup still says Needed, use **Repair approval after a rebuild**, then enable the freshly reset NotchPilot entry. This invokes `tccutil reset Accessibility org.notchpilot.app` and affects no other app. Always launch the installed `~/Applications/NotchPilot.app`; the run script uses that same location. If Microphone also says Needed, use Allow Microphone and approve its current prompt. Do not grant Full Disk Access to work around this problem. Rebuilds are not signed with an Apple Developer identity and are not notarized.

Use the microphone indicator in macOS to confirm capture stops after Escape or a second hotkey press. Sessions also stop after 60 seconds. Close Settings to return to the menu-bar-only experience.

If listening stops as soon as you release the shortcut, turn off **Hold to talk** in General. In toggle mode, releasing the key does not cancel; pressing it again does. Permission status should be checked after relaunch when a stale record has been reset.
