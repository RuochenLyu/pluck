#!/usr/bin/env bash
#
# Assembles Pluck.app from the SwiftPM product.
#
# There is deliberately no Xcode project (decisions.md 2026-07-27). Everything an .app
# needs that `swift build` does not do is done here, in ~60 readable lines: an Info.plist,
# a compiled String Catalog, an icon, and an ad-hoc signature. Signing for distribution
# and notarizing are `codesign`/`notarytool` on top of this output — neither needs a
# project file either.
#
#   ./Scripts/bundle.sh [debug|release]     → .build/Pluck.app
#
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SHORT_VERSION="0.1.0"
# Monotonic and derivable, so two builds of the same commit produce the same bundle.
BUILD_VERSION="$(git rev-list --count HEAD)"

APP="$ROOT/.build/Pluck.app"
CONTENTS="$APP/Contents"
RESOURCES="$CONTENTS/Resources"

echo "==> building PluckApp ($CONFIG)"
swift build -c "$CONFIG" --product PluckApp

BINARY="$ROOT/.build/$CONFIG/PluckApp"
[ -x "$BINARY" ] || { echo "no PluckApp binary at $BINARY" >&2; exit 1; }

echo "==> laying out $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$RESOURCES"
cp "$BINARY" "$CONTENTS/MacOS/Pluck"

sed -e "s/__SHORT_VERSION__/$SHORT_VERSION/" \
    -e "s/__BUILD_VERSION__/$BUILD_VERSION/" \
    "$ROOT/Packaging/Info.plist" > "$CONTENTS/Info.plist"
plutil -lint -s "$CONTENTS/Info.plist"

# The reason this script exists at all. SwiftPM copies `Localizable.xcstrings` into its
# resource bundle verbatim and never runs xcstringstool, so every lookup misses and falls
# back to the key — invisible while the key *is* the English copy, and silently fatal the
# day a second language is added. Compiling into `Contents/Resources/<lang>.lproj` also
# puts the strings where an .app is supposed to keep them, which is what lets `codesign`
# accept the bundle later.
echo "==> compiling the String Catalog"
xcrun xcstringstool compile \
    --output-directory "$RESOURCES" \
    "$ROOT/Sources/PluckApp/Resources/Localizable.xcstrings"
ls -d "$RESOURCES"/*.lproj > /dev/null

# The model manifest is trusted because it arrives inside the signature, not because of
# where it was found (product-plan §4.8): the signature vouches for the manifest, the
# manifest pins the URL and the digest, and the digest judges the bytes. So it is copied
# here, into the bundle being signed, rather than carried in SwiftPM's resource bundle —
# which this script does not ship, and which a `swift build` leaves holding a dangling
# symlink anyway. A dev shell run straight from `swift run` therefore offers no downloadable
# models, which is the honest answer: nothing has vouched for that manifest.
echo "==> copying the model manifest"
cp "$ROOT/models/manifest.json" "$RESOURCES/manifest.json"
# Not `plutil -lint`, which reads this as a plist and rejects it. A manifest that does not
# parse would leave the shipped app silently offering no models at all.
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$RESOURCES/manifest.json"

echo "==> drawing the icon"
swift "$ROOT/Scripts/make-icon.swift" "$RESOURCES/AppIcon.icns"

# Ad-hoc, so the bundle runs on this machine and the layout is validated now rather than
# on release day. `Scripts/release.sh` replaces this signature with a Developer ID one.
# The identifier is read back out of the plist rather than repeated here: two places to
# spell a bundle id is one place to get it wrong.
echo "==> signing (ad-hoc)"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$CONTENTS/Info.plist")"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"

echo "==> $APP"
du -sh "$APP" | cut -f1
