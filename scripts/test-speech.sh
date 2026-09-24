#!/bin/bash
source "$(dirname "$0")/common.sh"
NP_APP="$HOME/Applications/NotchPilot.app"
if [ ! -d "$NP_APP" ]; then echo 'Run ./scripts/bootstrap.sh first.'; exit 1; fi
mkdir -p .local
NP_FIXTURE="$NP_ROOT/.local/application-commands.aiff"
NP_REPORT="$NP_ROOT/.local/speech-commands.json"
say -v Samantha -r 125 -o "$NP_FIXTURE" 'Open Calculator, then open TextEdit.'
if ! afinfo "$NP_FIXTURE" | awk '/audio bytes:/ {ok=($3>0)} END {exit !ok}'; then
  echo 'macOS produced no audio. Run this in a normal Terminal with the Samantha voice available.'
  exit 1
fi
NP_MODE=--speech-command-smoke
if [ "${1:-}" = --microphone ]; then
  NP_MODE=--microphone-command-smoke
  echo 'This test plays synthetic speech through your speakers and listens through the approved microphone.'
  echo 'Use speakers, not headphones. It can only launch Calculator and TextEdit; it cannot type or send.'
fi
rm -f "$NP_REPORT"
pkill -x NotchPilot || true
open -n "$NP_APP" --args "$NP_MODE" "$NP_FIXTURE" "$NP_REPORT"
for ((NP_ATTEMPT=0; NP_ATTEMPT<45; NP_ATTEMPT++)); do
  [ -f "$NP_REPORT" ] && break
  sleep 1
done
python3 - "$NP_REPORT" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
if not p.exists(): sys.exit('No result yet. Check NotchPilot permissions and local speech assets.')
r=json.loads(p.read_text())
if r.get('speech_failed') or r.get('launched_apps')!=['calculator','textedit'] or r.get('duplicate_launches') or not r.get('real_launch_before_final'):
    print(json.dumps(r,indent=2));sys.exit('Speech integration did not pass. Check microphone/output routing when using --microphone.')
print('Passed: real speech launched Calculator and TextEdit in order with no duplicates.')
print('Launched before transcription finalized:',r['real_launch_before_final'])
PY
