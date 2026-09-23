#!/bin/bash
source "$(dirname "$0")/common.sh"
for tool in git python3 gh; do
    if ! command -v "$tool" >/dev/null; then printf 'Please install %s, then run bootstrap.sh again.\n' "$tool"; exit 1; fi
done
python3 -c 'import sys; assert sys.version_info >= (3, 11), "Python 3.11 or newer is required"'
python3 -m venv .venv
.venv/bin/python -m pip install -r sidecar/requirements.lock
if [ "${1:-}" != "--skip-model" ]; then
    .venv/bin/python sidecar/download_models.py
    .venv/bin/python scripts/configure_runtime.py
fi
./scripts/build.sh
./scripts/install.sh --built
printf '\nSetup complete. Run ./scripts/run.sh, then approve Microphone and Accessibility in Setup.\n'
