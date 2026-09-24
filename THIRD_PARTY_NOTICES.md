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

## MLX inference port

`sidecar/mlx_laya.py` is NotchPilot's modified MLX implementation of Laya's `common.py` choice sequence construction and typed decision head, using the same v0.3.7 checkpoint architecture. It replaces PyTorch operations, omits the unused action-probability head, uses local `tokenizers` files, and explicitly preserves float32 precision. Upstream vendored files remain available for reference comparisons; the application runtime does not import them. This is a source/runtime port, not fine-tuning.

MLX and MLX Metal 0.32.2 are developed by the MLX contributors and distributed under the MIT license: https://github.com/ml-explore/mlx/blob/main/LICENSE. Their wheels and license files are installed separately, not vendored. The ModernBERT encoder implementation follows the checkpoint configuration and the architecture documented by Hugging Face Transformers (Apache-2.0): https://github.com/huggingface/transformers/tree/main/src/transformers/models/modernbert. No Hugging Face model implementation is imported at runtime.

`sidecar/fixtures/mlx_reference.json` contains only project-authored synthetic commands and reference token IDs/probabilities. It contains no model weights or user data.
