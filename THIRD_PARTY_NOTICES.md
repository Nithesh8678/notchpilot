# Third-party notices

NotchPilot is an independent Apache-2.0 project. No affiliation with or endorsement by Laya, Convai Innovations, or Apple is implied.

## Laya

Source: https://github.com/NandhaKishorM/laya
Tag: v0.3.7
Commit: 010bacef009c855ccba814b51f7c8e1d38ab5e3f
License: Apache License 2.0 (see LICENSE).
Developed by Convai Innovations; upstream author metadata names Convai Innovations.

Reused files: `laya/agent.py` and `laya/common.py`, under `sidecar/vendor/laya/`.
Original notices are retained. NotchPilot supplies a minimal package initializer and an isolated local process wrapper instead of the upstream router, HTTP server, branding, and multi-checkpoint preloader. NotchPilot modifies agent.py to assign checkpoint tensors directly when loading, avoiding a second resident weight copy. The modification is marked in that file; common.py is unchanged.

Model weights are separate downloads, never committed. Setup records the pinned source revision, SHA-256 file manifest, and model card license in the local model cache. See docs/MODELS.md.
