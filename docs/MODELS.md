# Local models and evaluation

NotchPilot vendors only Laya `agent.py` and `common.py` from v0.3.7, commit `010bacef009c855ccba814b51f7c8e1d38ab5e3f`. See THIRD_PARTY_NOTICES.md for modifications and attribution. Neither the upstream router nor its HTTP server is used.

The English 421M and multilingual 322M checkpoints are Apache-2.0 according to their model cards. `sidecar/model-pins.json` records exact revisions. Setup checks the model-card license, verifies expected components, checks LFS SHA-256 hashes, and writes a local file manifest. Weights and downloaded model cards stay in Application Support; they are never committed. Runtime network access through Hugging Face is disabled.

`./scripts/bootstrap.sh` downloads only the default selected checkpoint. `./scripts/benchmark.sh` explicitly downloads both for comparison, then benchmarks them sequentially on CPU (1, 2 and 4 threads) and MPS (2 CPU threads, one inter-op worker). No run preloads multiple checkpoints. The runtime configuration uses the measured accuracy, p95 latency, and memory data. First-load imports and filesystem caches affect cold-start measurements; results are not GPU energy measurements.

The 48 committed synthetic cases are a small app-launch smoke dataset with separate calibration and test splits. They include unsupported and negative instructions. They are not a broad reliability certification. The initial evaluation did not clear the conservative confidence/margin gate, so optional Laya decisions abstain. Known commands remain fully deterministic. `action.act_probability` is never used.

No fine-tuning was performed: this small synthetic dataset is not sufficient to justify training a reliable macOS controller. Training on it and claiming held-out generality would be misleading. A future training effort needs independently labeled real-world sanitized intent/element cases, group-separated train/calibration/test splits, adversarial negatives, evaluation of abstention and false actions, and comparison against the frozen base models. No private user data is collected for training.

The vendor loader assigns checkpoint tensors, releases checkpoint references, then promotes to float32 to retain upstream inference behavior while reducing redundant resident copies where possible. Accuracy is remeasured after loader changes. A transient loading peak may exceed the steady-state target; see PERFORMANCE.md.
