#!/bin/sh
# Puts the licenses of everything in a packaged Legato.app (after macdeployqt, before signing) into Contents/Resources/Licenses:
# Legato's own (MPL 2.0), THIRD-PARTY-NOTICES.md, and the license files of each library bundled from Homebrew, as their licenses ask
# for binaries. Qt's own (LGPL 3, which refers to the GPL 3) come from qt/packaging/licenses, as Homebrew doesn't install them.
#
#   qt/packaging/collect-licenses.sh build/Legato.app
set -eu
app=$1
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
out="$app/Contents/Resources/Licenses"
brew=$(brew --prefix)
rm -rf "$out"
mkdir -p "$out"
cp "$repo/LICENSE" "$out/Legato-MPL-2.0.txt"
cp "$repo/THIRD-PARTY-NOTICES.md" "$out/"
cp "$repo/qt/fonts/TABLER-LICENSE.txt" "$out/Tabler-Icons-MIT.txt"

for lib in "$app/Contents/Frameworks/"*; do
    name=$(basename "$lib")
    src="$brew/lib/$name"
    [ -e "$src" ] || src=$(ls -d "$brew"/opt/*/lib/"$name" 2>/dev/null | head -1)
    [ -n "$src" ] && [ -e "$src" ] || { echo "collect-licenses: where $name came from isn't known" >&2; continue; }
    real=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$src")
    formula=$(echo "$real" | sed -nE "s|^$brew/Cellar/([^/]+)/([^/]+)/.*|\1|p")
    keg=$(echo "$real" | sed -nE "s|^($brew/Cellar/[^/]+/[^/]+)/.*|\1|p")
    [ -n "$formula" ] && [ ! -d "$out/$formula" ] || continue
    mkdir -p "$out/$formula"
    case "$formula" in
        qt*) cp "$here/licenses/LGPL-3.0.txt" "$here/licenses/GPL-3.0.txt" "$out/$formula/" ;;
        *) find "$keg" -maxdepth 1 -type f \( -iname 'license*' -o -iname 'licence*' -o -iname 'copying*' -o -iname 'copyright*' \
                -o -iname 'notice*' -o -iname '*gpl*.txt' \) -exec cp {} "$out/$formula/" \; ;;
    esac
    [ -n "$(ls -A "$out/$formula")" ] || echo "collect-licenses: no license file in $keg" >&2
done
echo "collect-licenses: $(ls "$out" | wc -l | tr -d ' ') entries in $out"
