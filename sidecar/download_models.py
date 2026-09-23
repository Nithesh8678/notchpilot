#!/usr/bin/env python3
"""Explicit setup-time downloads only. No user content is accepted by this program."""
import argparse
import hashlib
import json
import os
from pathlib import Path
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
from huggingface_hub import HfApi, snapshot_download

ROOT = Path(__file__).resolve().parent
CACHE = Path(os.environ.get('NOTCHPILOT_MODEL_DIR', Path.home() / 'Library/Application Support/NotchPilot/models'))
REPOS = {'english': 'convaiinnovations/laya', 'multilingual': 'convaiinnovations/laya-multilingual'}

def download(name):
    repo = REPOS[name]
    pins = json.loads((ROOT / 'model-pins.json').read_text()) if (ROOT / 'model-pins.json').exists() else {}
    info = HfApi().model_info(repo, revision=pins.get(name, {}).get('revision'), files_metadata=True)
    license_name = (info.card_data.to_dict() if info.card_data else {}).get('license')
    if license_name != 'apache-2.0':
        raise RuntimeError('Model license must be reviewed before download: ' + str(license_name))
    destination = CACHE / name
    patterns = ['rl_agent_config.json', 'model.safetensors', 'tokenizer/*', 'encoder/*', 'README.md', 'LICENSE*']
    snapshot_download(repo, revision=info.sha, local_dir=destination, allow_patterns=patterns, max_workers=3)
    required = ['model.safetensors', 'rl_agent_config.json', 'tokenizer/tokenizer.json', 'encoder/config.json']
    for file in required:
        if not (destination / file).is_file():
            raise RuntimeError('Missing model component: ' + file)
    manifest = {}
    for file in destination.rglob('*'):
        if not file.is_file() or '.cache' in file.parts:
            continue
        digest = hashlib.file_digest(file.open('rb'), 'sha256').hexdigest()
        relative = str(file.relative_to(destination))
        remote = next((f for f in info.siblings if f.rfilename == relative), None)
        if remote and remote.lfs and remote.lfs.sha256 != digest:
            raise RuntimeError('Model checksum mismatch: ' + relative)
        manifest[relative] = digest
    metadata = {'repo': repo, 'revision': info.sha, 'license': license_name, 'sha256': manifest}
    (destination / 'notchpilot-manifest.json').write_text(json.dumps(metadata, indent=2) + '\n')
    pins[name] = {'repo': repo, 'revision': info.sha, 'license': license_name}
    (ROOT / 'model-pins.json').write_text(json.dumps(pins, indent=2) + '\n')
    print(name + ': verified ' + info.sha, flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--all', action='store_true')
    args = parser.parse_args()
    for name in REPOS if args.all else [json.loads((ROOT / 'runtime-defaults.json').read_text())['model_name']]:
        download(name)
