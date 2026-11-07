#!/bin/bash
# Builds "Sims 3 Manager.app" and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Sims 3 Manager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Sims3Manager "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

if [ ! -f build/AppIcon.icns ]; then
    rm -rf build/AppIcon.iconset
    swift Resources/makeicon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --sign - "$APP"

mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Sims 3 Manager.app"
ditto "$APP" "$HOME/Applications/Sims 3 Manager.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Sims 3 Manager.app"
echo "Installed: $HOME/Applications/Sims 3 Manager.app"
