# Local models and evaluation

NotchPilot vendors only Laya `agent.py` and `common.py` from v0.3.7, commit `010bacef009c855ccba814b51f7c8e1d38ab5e3f`. See THIRD_PARTY_NOTICES.md for modifications and attribution. Neither the upstream router nor its HTTP server is used.

The English 421M and multilingual 322M checkpoints are Apache-2.0 according to their model cards. `sidecar/model-pins.json` records exact revisions. Setup checks the model-card license, verifies expected components, checks LFS SHA-256 hashes, and writes a local file manifest. Weights and downloaded model cards stay in Application Support; they are never committed. Runtime network access through Hugging Face is disabled.

`./scripts/bootstrap.sh` downloads only the selected multilingual checkpoint and installs an MLX-only runtime. `./scripts/benchmark.sh` explicitly downloads both pinned checkpoints and benchmarks each sequentially on MLX CPU and GPU. Only one checkpoint is resident per process. The selected multilingual/GPU backend has the best measured warm p95 and stays within the memory target. Deterministic routing works if the model is absent.

`sidecar/mlx_laya.py` is a modified MLX implementation of Laya's sequence builder, ModernBERT encoder and decision head. It uses the same pinned weights, including exact tokenizer IDs and action markers. `MLX_ENABLE_TF32=0` preserves reference precision on M5. On the 48 multilingual reference cases, all choices matched the frozen PyTorch CPU reference; maximum probability deviation was below 0.00005 (the reference rounds to four decimal places). Inference does not import Torch or Transformers. The unused act head is omitted. MLX allocation and process RSS are separate overlapping unified-memory measurements, not quantities to add together.

`sidecar/fixtures/mlx_reference.json` contains only synthetic evaluation text and token/probability reference data. The historical `benchmark_legacy_torch.py` requires separately installed legacy Torch/Transformers dependencies; it is not used in the production runtime and cannot change runtime selection. Historical CPU thread counts and MPS comparisons are retained in PERFORMANCE.md.

The 48 committed synthetic cases are a small app-launch smoke dataset with separate calibration and test splits. They include unsupported and negative instructions. They are not a broad reliability certification. The initial evaluation did not clear the conservative confidence/margin gate, so optional Laya decisions abstain. Known commands remain fully deterministic. `action.act_probability` is never used.

No fine-tuning was performed: this small synthetic dataset is not sufficient to justify training a reliable macOS controller. Training on it and claiming held-out generality would be misleading. A future training effort needs independently labeled real-world sanitized intent/element cases, group-separated train/calibration/test splits, adversarial negatives, evaluation of abstention and false actions, and comparison against the frozen base models. No private user data is collected for training.

