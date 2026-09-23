# Performance on the development Mac

Measured 2026-09-23 on Apple M5 Pro (15 CPU cores), 24 GB unified memory, macOS 26.6.2. These are local measurements, not general hardware guarantees.

## Laya: sequential synthetic evaluation

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

The selected configuration is multilingual / MPS with two CPU threads and one inter-op worker. It has the best measured p95 among configurations meeting the approximately 2.5 GB loading-memory budget. English had slightly higher ungated accuracy but exceeded that budget in the repeat matrix. Only one checkpoint is loaded in normal use.

MPS was faster on this Mac. The first inference is materially slower than warm inference. Fast response keeps the selected checkpoint warm; Low resource terminates the sidecar after session cancellation. The loader optimization retained the same measured top-1 accuracy. Peaks include transient loading allocations and are not steady resident measurements.

Process CPU time is an energy-related proxy, not measured watts or joules. No privileged powermetrics run was performed. Do not interpret these figures as battery-life claims.

## Native measurements

Latest installed release harness after moving Python dependencies into Application Support:

| Measurement | Observed result |
|---|---:|
| Parser-to-mock-adapter dispatch, 100 calls | p50 **0.066 ms**, p95 **0.176 ms** |
| Overlay window submission, 30 calls | p50 **5.44 ms**, p95 **8.56 ms** |
| Main-loop wake lateness during real Laya inference | p95 **1.24 ms** |
| Native resident memory after harness | **98.7 MB** |
| Later idle process snapshot with Settings open | **0.0% CPU**, approximately **111 MB RSS** |

The sidecar returned a gated abstention. Microphone permission was granted, but Accessibility was not. This run therefore does **not** verify the global hotkey, live microphone transcription, or WhatsApp control; its false hotkey results are blocked acceptance gates. The idle CPU figure is a snapshot, not a long-duration energy measurement. Real-time paced synthetic speech independently produced a stable app-opening clause before finalization.

An earlier installed run could not load the Python runtime from the Documents checkout. Installing a separate pinned runtime in Application Support resolved the observed failure without requesting broader file access.

Targets: hotkey callback to visible overlay p50 <50 ms; stable direct clause to dispatch p50 <150 ms/p95 <300 ms; idle CPU <1%; native and speech components approximately <500 MB; sidecar approximately <2.5 GB. Third-party cold launches are excluded.

Overlay submission measures the AppKit call, not display photon latency. Direct dispatch uses a mock adapter to isolate parser/queue overhead; actual application and AX timings are separate. Native RSS does not include Apple speech services hosted outside the app process. Current verified results and remaining gates are recorded in ACCEPTANCE.md.

Reproduce using `./scripts/benchmark.sh` after onboarding. Raw generated reports remain ignored under `benchmark-results/` and `.local/`. No private recordings or user content are used.
