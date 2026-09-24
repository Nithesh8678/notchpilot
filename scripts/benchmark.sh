#!/bin/bash
source "$(dirname "$0")/common.sh"
if [ ! -x .venv/bin/python ]; then echo 'Run ./scripts/bootstrap.sh first.'; exit 1; fi
.venv/bin/python sidecar/download_models.py --all
.venv/bin/python sidecar/benchmark.py
if [ ! -e "$HOME/Applications/NotchPilot.app" ]; then ./scripts/install.sh; fi
mkdir -p .local
printf 'Approve the app permissions before the native benchmark. No real messages are sent.\n'
pkill -x NotchPilot || true
open -n "$HOME/Applications/NotchPilot.app" --args --acceptance-report "${TMPDIR:-/tmp}/notchpilot-native-benchmark.json"
printf 'Laya results: benchmark-results/mlx.json\nNative results: %s/notchpilot-native-benchmark.json\n' "${TMPDIR:-/tmp}"
