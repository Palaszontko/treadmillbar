#!/bin/bash
# Usage: ./build.sh          build build/TreadmillBar.app
#        ./build.sh install  also copy to ~/Applications and launch
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/TreadmillBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TreadmillBar "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x TreadmillBar && sleep 1 || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/TreadmillBar.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/TreadmillBar.app
    echo "installed ~/Applications/TreadmillBar.app"
fi
