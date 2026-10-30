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
# Linux (the AppImage's icon: desktop icon themes stop at 512)
render "$root/qt/icons/legato-512.png" 512 macos
# macOS: Legato.app's icon in Finder and the Applications folder (iconutil, from the sizes macOS asks for)
if command -v iconutil >/dev/null; then
    set_dir=$(mktemp -d)/legato.iconset
    mkdir -p "$set_dir"
    for s in 16 32 128 256 512; do
        render "$set_dir/icon_${s}x${s}.png" $s macos
        render "$set_dir/icon_${s}x${s}@2x.png" $((s * 2)) macos
    done
    iconutil -c icns "$set_dir" -o "$root/qt/icons/legato.icns"
fi
# Android: the adaptive icon's foreground (its background is the colour in values/ic_launcher.xml)
render "$root/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png" 432 foreground
render "$here/icon-preview.png" 512 rounded
echo "icons written"
