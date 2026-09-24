#!/usr/bin/env python3
"""Install a private runtime outside protected source folders; keep paths local."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
support = Path.home() / 'Library/Application Support/NotchPilot'
support.mkdir(parents=True, exist_ok=True, mode=0o700)
lock = (root / 'sidecar/requirements.lock').read_bytes()
fingerprint = hashlib.sha256(lock + sys.version.encode()).hexdigest()[:12]
runtime = support / ('runtime-mlx-' + fingerprint)
python = runtime / 'bin/python3'
marker = runtime / '.notchpilot-runtime-ready'
if not marker.exists():
    # Keep the development .venv project-local, but do not make the installed app
    # request access to Documents/Desktop just to import its own dependencies.
    if Path(sys.prefix).resolve() != (root / '.venv').resolve():
        raise SystemExit('Run this script with .venv/bin/python after bootstrap dependencies.')
    subprocess.run([sys._base_executable, '-m', 'venv', str(runtime)], check=True)
    subprocess.run([str(python), '-m', 'pip', 'install', '--disable-pip-version-check', '-r', str(root / 'sidecar/requirements.lock')], check=True)
    marker.write_text(fingerprint + '\n')
    runtime.chmod(0o700)
config = support / 'runtime.json'
defaults = json.loads(config.read_text()) if config.exists() else json.loads(
    (root / 'sidecar/runtime-defaults.json').read_text())
defaults['python'] = str(python)
defaults['runtime'] = 'mlx'
defaults['backend'] = 'gpu'
defaults['model_name'] = 'multilingual'
defaults['model'] = str(support / 'models' / defaults['model_name'])
config.write_text(json.dumps(defaults, indent=2) + '\n')
config.chmod(0o600)
print('Local model runtime ready in Application Support. Use benchmark.sh to measure this Mac.')
