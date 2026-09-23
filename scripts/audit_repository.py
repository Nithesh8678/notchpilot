#!/usr/bin/env python3
"""Check the publishable file set, not the ignored local caches."""
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
files = subprocess.check_output(['git','ls-files','-z'], cwd=root).decode().split('\0')
errors = []
for name in filter(None,files):
    if any(p in {'.venv','.build','build','.local','models','__pycache__'} for p in Path(name).parts) or Path(name).suffix in {'.safetensors','.pt','.pth','.aiff','.wav','.pyc'}:
        errors.append('Generated or private file tracked: '+name)
    path = root/name
    if path.is_file():
        text = path.read_text(errors='ignore')
        # No machine-specific account paths or credentials in the publishable source.
        if '/Users/' in text or 'ghp_' in text or 'github_pat_' in text:
            errors.append('Potential private data in: '+name)
for required in ['LICENSE','THIRD_PARTY_NOTICES.md','PRIVACY.md','SECURITY.md']:
    if not (root/required).is_file(): errors.append('Missing '+required)
print('\n'.join(errors) if errors else 'Repository privacy and attribution checks passed.')
sys.exit(bool(errors))
