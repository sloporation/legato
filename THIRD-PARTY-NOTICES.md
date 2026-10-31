# Third-party notices

Legato is licensed under the [Mozilla Public License 2.0](LICENSE). It is built on the open source software below, which keeps its
own license. The packaged apps carry these licenses' full texts: Legato Desktop for macOS in `Legato.app/Contents/Resources/Licenses`
(put there by `qt/packaging/collect-licenses.sh`).

## Legato Desktop

| Software | Used for | License |
|---|---|---|
| [Qt 6](https://www.qt.io/) | the app's window, QML, playback (Qt Multimedia), networking | LGPL-3.0 |
| [TagLib](https://taglib.org/) | reading and writing tags | LGPL-2.1 or MPL-1.1 |
| [libyaml](https://github.com/yaml/libyaml) | the settings file | MIT |
| [libimobiledevice](https://libimobiledevice.org/), libimobiledevice-glue, libplist, libusbmuxd | syncing to iPhones | LGPL-2.1-or-later |
| [libmtp](https://libmtp.sourceforge.net/) | syncing to Android phones | LGPL-2.1-or-later |
| [libusb](https://libusb.info/) | USB, for libmtp | LGPL-2.1-or-later |
| [OpenSSL](https://openssl-library.org/) | secure connections (Qt, libimobiledevice) | Apache-2.0 |
| [Tabler Icons](https://tabler.io/icons) | the icons | MIT |

The macOS app also bundles the libraries these use, as Homebrew builds them:

| Software | License |
|---|---|
| [GLib](https://docs.gtk.org/glib/), [gettext](https://www.gnu.org/software/gettext/)'s libintl | LGPL-2.1-or-later |
| [D-Bus](https://www.freedesktop.org/wiki/Software/dbus/) | AFL-2.1 |
| [ICU](https://icu.unicode.org/) | Unicode-3.0 |
| [FreeType](https://freetype.org/) | FTL |
| [HarfBuzz](https://harfbuzz.github.io/), [Brotli](https://github.com/google/brotli), [Little CMS](https://www.littlecms.com/), [MD4C](https://github.com/mity/md4c) | MIT |
| [Graphite](https://graphite.sil.org/) | MIT (one of its choices) |
| [PCRE2](https://www.pcre.org/), [double-conversion](https://github.com/google/double-conversion), [WebP](https://developers.google.com/speed/webp/) | BSD-3-Clause |
| [Zstandard](https://facebook.github.io/zstd/) | BSD-3-Clause |
| [XZ Utils](https://tukaani.org/xz/)' liblzma | 0BSD |
| [libjpeg-turbo](https://libjpeg-turbo.org/) | IJG, BSD-3-Clause and Zlib |
| [libpng](http://www.libpng.org/pub/png/libpng.html) | libpng-2.0 |
| [LibTIFF](https://libtiff.gitlab.io/libtiff/) | libtiff |
| [JasPer](https://jasper-software.github.io/jasper/) | JasPer-2.0 |
| [libmng](https://sourceforge.net/projects/libmng/) | Zlib |
| [BLAKE2](https://blake2.net/) (libb2) | CC0-1.0 |

The libraries under the LGPL are linked dynamically and ship as separate files in the app (`Contents/Frameworks` on macOS), so you can
replace them with your own builds. Their source code is at the links above; the exact versions in a release are those its CI build
installed (see `.github/workflows/build.yml`), and are available on request from the maintainers of this repository for three years
after that release.

[ffmpeg](https://ffmpeg.org/) is not part of Legato: when it is installed, Legato runs it as a separate program to convert music a phone
can't play.

## Legato for Android

| Software | License |
|---|---|
| [AndroidX](https://developer.android.com/jetpack/androidx), including [Jetpack Compose](https://developer.android.com/compose) and [Media3](https://developer.android.com/media/media3) | Apache-2.0 |
| [Kotlin](https://kotlinlang.org/) standard library and coroutines | Apache-2.0 |
| [Tabler Icons](https://tabler.io/icons) | MIT |

## Legato for iPhone and Apple Watch

Built only on Apple's frameworks; no third-party code.
