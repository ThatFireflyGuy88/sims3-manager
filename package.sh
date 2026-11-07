#!/bin/bash
# Builds the app and makes a zip to share: "dist/Sims 3 Manager <version>.zip".
# Apple Silicon only.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

APP="build/Sims 3 Manager.app"
BIN="$APP/Contents/MacOS/Sims3Manager"
ARCHS=$(lipo -archs "$BIN")
if [ "$ARCHS" != "arm64" ]; then
    echo "Expected an Apple Silicon (arm64) only build, got: $ARCHS" >&2
    exit 1
fi
codesign --verify --strict "$APP"

VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
STAGE="build/dist-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE" dist
ditto "$APP" "$STAGE/Sims 3 Manager.app"
cp README.md "$STAGE/README.md"

ZIP="dist/Sims 3 Manager $VERSION.zip"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --noqtn "$STAGE" "$ZIP"
rm -rf "$STAGE"
echo "Packaged: $ZIP ($(du -h "$ZIP" | cut -f1), $ARCHS)"
