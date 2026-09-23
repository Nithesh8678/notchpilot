#!/bin/bash
source "$(dirname "$0")/common.sh"
./scripts/test.sh
./scripts/build.sh
NP_REAL_APP="$(cd build/NotchPilot.app && pwd -P)"
ditto -c -k --sequesterRsrc --keepParent "$NP_REAL_APP" build/NotchPilot-0.1.0-local.zip
printf 'Created build/NotchPilot-0.1.0-local.zip (ad-hoc local build; not notarized).\n'
