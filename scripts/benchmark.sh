#!/bin/bash
source "$(dirname "$0")/common.sh"
if [ ! -x .venv/bin/python ]; then echo 'Run ./scripts/bootstrap.sh first.'; exit 1; fi
.venv/bin/python sidecar/download_models.py --all
.venv/bin/python sidecar/benchmark.py
./scripts/build.sh
mkdir -p .local
printf 'Approve the app permissions before the native benchmark. No real messages are sent.\n'
open "$NP_ROOT/build/NotchPilot.app" --args --acceptance-report "$NP_ROOT/.local/native.json"
printf 'Laya results: benchmark-results/laya.json\nNative results: .local/native.json\n'
