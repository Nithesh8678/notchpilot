#!/bin/bash
source "$(dirname "$0")/common.sh"
if [ ! -d "$HOME/Applications/NotchPilot.app" ]; then ./scripts/install.sh; fi
open "$HOME/Applications/NotchPilot.app" --args "$@"
