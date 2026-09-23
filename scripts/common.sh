#!/bin/bash
set -euo pipefail
NP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$NP_ROOT"
if ! command -v swift >/dev/null; then echo 'Install Xcode Command Line Tools: xcode-select --install'; exit 1; fi
if ! swift --version >/dev/null 2>&1 && [ -d /Library/Developer/CommandLineTools ]; then export DEVELOPER_DIR=/Library/Developer/CommandLineTools; fi
export CLANG_MODULE_CACHE_PATH="$NP_ROOT/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$NP_ROOT/.build/module-cache"
export USE_TF=0 TOKENIZERS_PARALLELISM=false HF_HUB_DISABLE_TELEMETRY=1
