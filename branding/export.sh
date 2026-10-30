#!/bin/sh
# Regenerates every app icon from icon.svg. Run from anywhere after changing the SVG:  branding/export.sh
set -e
here=$(cd "$(dirname "$0")" && pwd)
root="$here/.."
cmake -S "$here/tools" -B "$here/tools/build" -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt >/dev/null
cmake --build "$here/tools/build" >/dev/null
render() { QT_QPA_PLATFORM=offscreen "$here/tools/build/render" "$here/icon.svg" "$@"; }

render "$root/ios/Legato/Assets.xcassets/AppIcon.appiconset/icon-1024.png" 1024 square
render "$root/ios/LegatoWatch/Assets.xcassets/AppIcon.appiconset/icon-1024.png" 1024 square
render "$root/qt/icons/legato.png" 1024 macos
render "$here/icon-preview.png" 512 rounded
echo "icons written"
