#!/bin/bash
source "$(dirname "$0")/common.sh"
NP_CONFIGURATION="${1:-release}"
swift build --build-system native --disable-sandbox -c "$NP_CONFIGURATION" -j 4
NP_BIN="$(swift build --build-system native --disable-sandbox -c "$NP_CONFIGURATION" --show-bin-path)"
NP_OUTPUT="${NOTCHPILOT_BUILD_DIR:-${TMPDIR:-/tmp}/notchpilot-build-$UID}"
NP_APP="$NP_OUTPUT/NotchPilot.app"
mkdir -p "$NP_APP/Contents/MacOS" "$NP_APP/Contents/Resources/sidecar/vendor/laya"
find "$NP_APP/Contents/Resources/sidecar" -type d -name __pycache__ -prune -exec rm -rf {} +
cp "$NP_BIN/NotchPilot" "$NP_APP/Contents/MacOS/NotchPilot"
cp Resources/Info.plist "$NP_APP/Contents/Info.plist"
cp sidecar/service.py sidecar/protocol.py "$NP_APP/Contents/Resources/sidecar/"
cp sidecar/vendor/laya/*.py "$NP_APP/Contents/Resources/sidecar/vendor/laya/"
cp LICENSE THIRD_PARTY_NOTICES.md "$NP_APP/Contents/Resources/"
# Finder metadata from sync providers is not code and invalidates ad-hoc signing.
xattr -cr "$NP_APP"
codesign --force --sign - --identifier org.notchpilot.app "$NP_APP"
codesign --verify --strict "$NP_APP"
mkdir -p "$NP_ROOT/build"
if [ -d "$NP_ROOT/build/NotchPilot.app" ] && [ ! -L "$NP_ROOT/build/NotchPilot.app" ]; then
    mv "$NP_ROOT/build/NotchPilot.app" "$NP_ROOT/build/NotchPilot.previous.app"
fi
ln -sfn "$NP_APP" "$NP_ROOT/build/NotchPilot.app"
printf 'Built %s\n' "$NP_APP"
