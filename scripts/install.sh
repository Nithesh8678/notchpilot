#!/bin/bash
source "$(dirname "$0")/common.sh"
if [ "${1:-}" != "--built" ]; then ./scripts/build.sh; fi
NP_SOURCE_APP="$(cd build/NotchPilot.app && pwd -P)"
NP_INSTALLED_APP="$HOME/Applications/NotchPilot.app"
if [ -e "$NP_INSTALLED_APP" ]; then
    NP_EXISTING_ID="$(plutil -extract CFBundleIdentifier raw "$NP_INSTALLED_APP/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$NP_EXISTING_ID" != org.notchpilot.app ]; then echo 'A different app already occupies ~/Applications/NotchPilot.app. Move it before installing.'; exit 1; fi
fi
mkdir -p "$HOME/Applications"
if [ "$NP_SOURCE_APP" != "$NP_INSTALLED_APP" ]; then ditto "$NP_SOURCE_APP" "$NP_INSTALLED_APP"; fi
find "$NP_INSTALLED_APP/Contents/Resources/sidecar" -type d -name __pycache__ -prune -exec rm -rf {} +
xattr -cr "$NP_INSTALLED_APP"
codesign --verify --strict "$NP_INSTALLED_APP"
ln -sfn "$NP_INSTALLED_APP" "$NP_ROOT/build/NotchPilot.app"
printf 'Installed %s\n' "$NP_INSTALLED_APP"
