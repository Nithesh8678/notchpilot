#!/usr/bin/env python3
"""Write machine-local paths only to Application Support, never into source."""
import json
import os
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
support = Path.home() / 'Library/Application Support/NotchPilot'
support.mkdir(parents=True, exist_ok=True, mode=0o700)
config = support / 'runtime.json'
if not config.exists():
    defaults = json.loads((root / 'sidecar/runtime-defaults.json').read_text())
    defaults['python'] = sys.executable
    defaults['model'] = str(support / 'models' / defaults['model_name'])
    config.write_text(json.dumps(defaults, indent=2)+'\n')
    config.chmod(0o600)
print('Local model configuration ready. Use benchmark.sh to measure this Mac.')
