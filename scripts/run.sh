#!/bin/bash
source "$(dirname "$0")/common.sh"
if [ ! -d build/NotchPilot.app ]; then ./scripts/build.sh; fi
open "$NP_ROOT/build/NotchPilot.app" --args "$@"
