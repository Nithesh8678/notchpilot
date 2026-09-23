#!/bin/bash
source "$(dirname "$0")/common.sh"
swift test --build-system native --disable-sandbox -j 4
python3 -m unittest discover -s sidecar/tests -v
