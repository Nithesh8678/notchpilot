# Performance on the development Mac

Measured 2026-09-23 on Apple M5 Pro (15 CPU cores), 24 GB unified memory, macOS 26.6.2. These are local measurements, not general hardware guarantees.

## Historical PyTorch comparison (2026-09-23)

48 app-launch and unsupported-command cases per configuration. Accuracy is ungated top-1; the production confidence gate currently abstains. Loading includes Python imports and model initialization. Each configuration runs in a separate process; later runs benefit from filesystem caches.

| Checkpoint | Backend / threads | Load ms | First inference ms | Warm p50 / p95 ms | Peak RSS MB | Accuracy | CPU seconds / 48 cases |
|---|---|---:|---:|---:|---:|---:|---:|
| english | cpu / 1 | 2233 | 196.2 | 88.2 / 89.3 | 2826 | 87.5% | 4.32 |
| english | cpu / 2 | 1904 | 151.9 | 87.1 / 91.8 | 2822 | 87.5% | 4.64 |
| english | cpu / 4 | 1794 | 128.3 | 86.0 / 93.9 | 2824 | 87.5% | 5.02 |
| english | mps / 2 | 2447 | 263.5 | 30.6 / 37.0 | 2824 | 87.5% | 0.46 |
| multilingual | cpu / 1 | 3022 | 62.6 | 34.7 / 35.4 | 2555 | 85.4% | 1.68 |
| multilingual | cpu / 2 | 2747 | 46.0 | 35.1 / 37.6 | 2556 | 85.4% | 1.88 |
| multilingual | cpu / 4 | 2736 | 43.8 | 34.8 / 36.2 | 2557 | 85.4% | 2.04 |
| multilingual | mps / 2 | 2987 | 129.5 | 14.6 / 22.7 | 2559 | 85.4% | 0.33 |

The initial PyTorch selection was multilingual / MPS with two CPU threads and one inter-op worker; it is superseded by MLX below. It has the best measured p95 among configurations meeting the approximately 2.5 GB loading-memory budget. English had slightly higher ungated accuracy but exceeded that budget in the repeat matrix. Only one checkpoint is loaded in normal use.

MPS was faster on this Mac. The first inference is materially slower than warm inference. Fast response keeps the selected checkpoint warm; Low resource terminates the sidecar after session cancellation. The loader optimization retained the same measured top-1 accuracy. Peaks include transient loading allocations and are not steady resident measurements.

Process CPU time is an energy-related proxy, not measured watts or joules. No privileged powermetrics run was performed. Do not interpret these figures as battery-life claims.

## Current MLX runtime (2026-09-24)

Same machine, same pinned checkpoints and 48 synthetic cases. Strict float32 reference mode (`MLX_ENABLE_TF32=0`); sequential isolated processes. Loading includes local tokenizer/model initialization; later processes benefit from filesystem and Metal compiler caches.

| Checkpoint | Backend | Load ms | First inference ms | Warm p50 / p95 ms | Peak RSS MB | MLX peak MB | Top-1 accuracy |
|---|---|---:|---:|---:|---:|---:|---:|
| Multilingual 322M | CPU | 474.3 | 4060.7 | 34.67 / 35.17 | 1744.8 | 1355.2 | 85.4% |
| **Multilingual 322M** | **GPU (selected)** | **391.6** | **23.77** | **8.27 / 8.52** | **895.4** | **1840.8** | **85.4%** |
| English 421M | CPU | 234.9 | 168.7 | 91.31 / 107.23 | 1775.3 | 1705.7 | 87.5% |
| English 421M | GPU | 134.6 | 66.71 | 19.33 / 20.06 | 762.3 | 2214.4 | 87.5% |

The selected model matched every original reference choice with probability deviation below 0.00005. A separate colder strict-mode GPU run loaded in 884.9 ms, first inferred in 265 ms, and warmed to 8.66 / 8.98 ms. Cold compilation can take seconds: the matrix CPU first call demonstrates this. The production confidence gate still abstains; these accuracy figures do not justify unrestricted automation or a training claim. No fine-tuning was performed.

Process RSS and MLX allocated memory overlap on unified-memory hardware; do not sum them. Selected GPU process CPU time was 0.225 seconds for 48 cases (CPU backend 1.967 seconds). This is an energy proxy, not a watts/battery measurement. The native app remains usable while the sidecar prepares, and model absence never blocks direct commands.

## Current native measurements (2026-09-24)

Installed release with the MLX runtime, 100 direct dispatch samples and 30 overlay submissions:

| Measurement | Observed result |
|---|---:|
| Stable parser-to-mock-adapter dispatch | p50 **0.106 ms**, p95 **0.164 ms** |
| Overlay window submission | p50 **5.32 ms**, p95 **7.30 ms** |
| Main-loop wake lateness during real MLX inference | p95 **1.23 ms** |
| Native resident memory after harness | **110.8 MB** |
| 20-second idle sample with Settings open | median **0.0% CPU**, **97.5 MB RSS** |

The sidecar returned its expected gated abstention. Both permissions were approved. Global hotkey start, second-press stop and Escape cancellation passed in toggle mode. Actual hotkey callback-to-overlay submission was 9.23 ms in this run. App launching through the production adapter succeeded for Calculator, TextEdit, Safari and Finder; the catalog discovered 98 installed apps. Discovery count does not certify control of every app.

The 20-second idle sample is not a long-duration energy measurement. Earlier real-time paced synthetic speech independently produced a stable app-opening clause before finalization. Native memory excludes the separate MLX process and speech services hosted by macOS. The installed signature verified after model inference, with Python bytecode writes into the signed bundle disabled.

Targets: hotkey callback to visible overlay p50 <50 ms; stable direct clause to dispatch p50 <150 ms/p95 <300 ms; idle CPU <1%; native and speech components approximately <500 MB; sidecar approximately <2.5 GB. Third-party cold launches are excluded.

Overlay submission measures the AppKit call, not display photon latency. Direct dispatch uses a mock adapter to isolate parser/queue overhead; actual application and AX timings are separate. Native RSS does not include Apple speech services hosted outside the app process. Current verified results and remaining gates are recorded in ACCEPTANCE.md.

Reproduce using `./scripts/benchmark.sh` after onboarding. Raw generated reports remain ignored under `benchmark-results/` and `.local/`. No private recordings or user content are used.
