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
FRAMEWORKS="$CONTENTS/Frameworks"

# Sparkle's EdDSA public key, if this machine has one. Not a secret — it is compiled into
# every copy of the app — but it is also not in the repository, because it is the public
# half of a key pair that does not exist until the maintainer runs Sparkle's `generate_keys`
# (see Scripts/release.sh). Absent, the bundle is built without it and ships with automatic
# updates switched off rather than with an updater that trusts nothing in particular.
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
if [ -z "$SPARKLE_PUBLIC_ED_KEY" ] && [ -f "$ROOT/Packaging/sparkle_public_key.txt" ]; then
    SPARKLE_PUBLIC_ED_KEY="$(tr -d '[:space:]' < "$ROOT/Packaging/sparkle_public_key.txt")"
fi

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
    -e "s|__SPARKLE_PUBLIC_ED_KEY__|$SPARKLE_PUBLIC_ED_KEY|" \
    "$ROOT/Packaging/Info.plist" > "$CONTENTS/Info.plist"
# An empty key is not a key. Deleting it is what makes `UpdateController` decline to start
# Sparkle at all — which is the point: Sparkle's own reaction to a missing key is an alert
# telling the user to contact the developer, and that must not be what a build-from-source
# does to somebody.
if [ -z "$SPARKLE_PUBLIC_ED_KEY" ]; then
    plutil -remove SUPublicEDKey "$CONTENTS/Info.plist"
    echo "    no Sparkle public key — this build will not check for updates"
fi
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

# The Finder Quick Action. Compiled with bare swiftc rather than a SwiftPM target for two
# reasons: the extension entry point needs `-e _NSExtensionMain`, which SwiftPM only
# expresses as unsafeFlags (poisoning PluckKit for every downstream consumer — the same
# trade rejected for Sparkle's rpath), and the extension is deliberately one file with no
# dependencies: it forwards the selected files to the app and exits. See the header of
# ActionRequestHandler.swift for why it must not matte anything itself.
echo "==> building the Finder Quick Action"
APPEX="$CONTENTS/PlugIns/PluckQuickAction.appex"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
xcrun swiftc -O \
    -module-name PluckQuickAction \
    -target arm64-apple-macos26.0 \
    -framework AppKit \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$APPEX/Contents/MacOS/PluckQuickAction" \
    "$ROOT/Extensions/FinderQuickAction/ActionRequestHandler.swift"
sed -e "s/__SHORT_VERSION__/$SHORT_VERSION/" \
    -e "s/__BUILD_VERSION__/$BUILD_VERSION/" \
    "$ROOT/Extensions/FinderQuickAction/Info.plist" > "$APPEX/Contents/Info.plist"
plutil -lint -s "$APPEX/Contents/Info.plist"
cp -R "$ROOT/Extensions/FinderQuickAction/en.lproj" \
      "$ROOT/Extensions/FinderQuickAction/zh-Hans.lproj" \
      "$APPEX/Contents/Resources/"
cp "$RESOURCES/AppIcon.icns" "$APPEX/Contents/Resources/AppIcon.icns"

# Sparkle is a framework, and a framework in an .app has to be carried inside it — SwiftPM
# leaves it beside the binary in `.build/<config>/`, which is a build directory nobody
# ships. `ditto` rather than `cp -R`: the framework is a versioned bundle held together by
# symlinks (Versions/Current, and eight top-level links into it), and a copy that resolved
# them would double the size and fail `codesign --verify`.
#
# The rpath is added here rather than in Package.swift because the alternative is
# `unsafeFlags`, and a package that uses those cannot be depended on by any other package —
# a real cost, paid by PluckKit's consumers, for a linker flag that only the .app needs.
echo "==> embedding Sparkle"
SPARKLE_FRAMEWORK="$ROOT/.build/$CONFIG/Sparkle.framework"
[ -d "$SPARKLE_FRAMEWORK" ] || { echo "no Sparkle.framework at $SPARKLE_FRAMEWORK" >&2; exit 1; }
mkdir -p "$FRAMEWORKS"
ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS/Sparkle.framework"
# Headers are a development artifact: nothing at runtime reads them, and they are 20 files
# `codesign` would otherwise have to seal into the bundle's signature.
rm -rf "$FRAMEWORKS/Sparkle.framework/Versions/B/Headers" \
       "$FRAMEWORKS/Sparkle.framework/Versions/B/PrivateHeaders" \
       "$FRAMEWORKS/Sparkle.framework/Versions/B/Modules" \
       "$FRAMEWORKS/Sparkle.framework/Headers" \
       "$FRAMEWORKS/Sparkle.framework/PrivateHeaders" \
       "$FRAMEWORKS/Sparkle.framework/Modules"
install_name_tool -add_rpath @executable_path/../Frameworks "$CONTENTS/MacOS/Pluck" 2>/dev/null \
    || echo "    rpath already present"

# Ad-hoc by default, so the bundle runs on this machine and the layout is validated now
# rather than on release day. `Scripts/release.sh` sets `CODESIGN_IDENTITY` and gets the
# same layout signed for distribution — the *order* below is the part that must not exist
# twice, because a bundle with nested code signed after its container is a bundle Gatekeeper
# rejects, and finding that out on release day is finding it out too late.
#
# The identifier is read back out of the plist rather than repeated here: two places to
# spell a bundle id is one place to get it wrong. It is applied to the app alone — the
# framework and everything under it keep the identifiers Sparkle gave them, which is what
# their Info.plists and their XPC service lookups expect.
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

# A function rather than an array of flags: `set -u` and bash 3.2 — which is the bash macOS
# ships — make expanding a possibly-empty array a footgun, and this reads better anyway.
# `--options runtime` is what notarization requires; `--timestamp` is what keeps a signature
# valid after the certificate behind it expires. Neither means anything ad-hoc.
sign() {
    if [ "$SIGN_IDENTITY" = "-" ]; then
        codesign --force --sign - "$@"
    else
        codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$@"
    fi
}

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> signing (ad-hoc)"
else
    echo "==> signing ($SIGN_IDENTITY)"
fi
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$CONTENTS/Info.plist")"

# Inside out. Sparkle is four pieces of nested code — two XPC services, the relaunch helper
# and the progress app — and each seals into the framework, which seals into the app.
SPARKLE_VERSION="$FRAMEWORKS/Sparkle.framework/Versions/B"
for nested in \
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc" \
    "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
    "$SPARKLE_VERSION/Autoupdate" \
    "$SPARKLE_VERSION/Updater.app" \
    "$SPARKLE_VERSION"
do
    sign "$nested"
done

# The extension seals before the app that carries it, and it must carry its sandbox
# entitlements even ad-hoc: an unsandboxed extension is one the system refuses to load,
# and that refusal should surface on today's build, not on release day.
sign --entitlements "$ROOT/Extensions/FinderQuickAction/PluckQuickAction.entitlements" \
    "$CONTENTS/PlugIns/PluckQuickAction.appex"

sign --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> $APP"
du -sh "$APP" | cut -f1
