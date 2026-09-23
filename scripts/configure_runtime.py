#!/usr/bin/env python3
"""Install a private runtime outside protected source folders; keep paths local."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import sysconfig

root = Path(__file__).resolve().parents[1]
support = Path.home() / 'Library/Application Support/NotchPilot'
support.mkdir(parents=True, exist_ok=True, mode=0o700)
lock = (root / 'sidecar/requirements.lock').read_bytes()
fingerprint = hashlib.sha256(lock + sys.version.encode()).hexdigest()[:12]
runtime = support / ('runtime-' + fingerprint)
python = runtime / 'bin/python3'
marker = runtime / '.notchpilot-runtime-ready'
if not marker.exists():
    # Keep the development .venv project-local, but do not make the installed app
    # request access to Documents/Desktop just to import its own dependencies.
    if Path(sys.prefix).resolve() != (root / '.venv').resolve():
        raise SystemExit('Run this script with .venv/bin/python after bootstrap dependencies.')
    subprocess.run([sys._base_executable, '-m', 'venv', '--without-pip', str(runtime)], check=True)
    destination = subprocess.check_output(
        [str(python), '-c', 'import sysconfig; print(sysconfig.get_path("purelib"))'], text=True).strip()
    shutil.copytree(sysconfig.get_path('purelib'), destination, dirs_exist_ok=True)
    marker.write_text(fingerprint + '\n')
    runtime.chmod(0o700)
config = support / 'runtime.json'
defaults = json.loads(config.read_text()) if config.exists() else json.loads(
    (root / 'sidecar/runtime-defaults.json').read_text())
defaults['python'] = str(python)
defaults['model'] = str(support / 'models' / defaults['model_name'])
config.write_text(json.dumps(defaults, indent=2) + '\n')
config.chmod(0o600)
print('Local model runtime ready in Application Support. Use benchmark.sh to measure this Mac.')
