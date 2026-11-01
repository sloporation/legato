#!/bin/sh
# Builds TagLib as static libraries for Legato for Mac, into TagLib/out (not kept in git): libtag.a and the C API libtag_c.a, for Apple
# silicon and Intel, with tag_c.h and a module map so Swift can `import TagLibC`. TagLib is LGPL-2.1 or MPL-1.1: Legato takes it under
# the MPL, which allows linking it into the app. Xcode runs this before building the Mac app; it does nothing once out/ is there.
# Needs cmake (brew install cmake). zlib (for compressed ID3v2 frames) is the one in macOS.
set -eu
VERSION=2.3.2
SHA256=3ca2d8afaa7f1cf7f6ed10e511ebc368bfacd6dcaa3dbfa690b89e502e8963dc
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/out"
STAMP="$OUT/.taglib-$VERSION"
[ -f "$STAMP" ] && exit 0

PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"     # (Xcode's build scripts don't get Homebrew's)
WORK="$DIR/work"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK"
curl -fsSL "https://taglib.org/releases/taglib-$VERSION.tar.gz" -o "$WORK/taglib.tar.gz"
echo "$SHA256  $WORK/taglib.tar.gz" | shasum -a 256 -c -
tar -xzf "$WORK/taglib.tar.gz" -C "$WORK"

cmake -S "$WORK/taglib-$VERSION" -B "$WORK/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_BINDINGS=ON \
    -DBUILD_TESTING=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DWITH_ZLIB=ON \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_INSTALL_PREFIX="$OUT"
cmake --build "$WORK/build" --parallel
cmake --install "$WORK/build"

# the C API as a Swift module
mkdir -p "$OUT/include/TagLibC"
cp "$OUT/include/taglib/tag_c.h" "$OUT/include/TagLibC/"
cat > "$OUT/include/TagLibC/module.modulemap" <<'MAP'
module TagLibC {
    header "tag_c.h"
    link "tag_c"
    link "tag"
    link "c++"
    link "z"
    export *
}
MAP
rm -rf "$WORK"
touch "$STAMP"
