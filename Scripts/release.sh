#!/usr/bin/env bash
#
# Signs, notarizes and staples Pluck.app, then zips it for GitHub Releases.
#
# Prerequisites, all one-time and all on the developer's machine:
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates… ▸ + )
#   2. A stored notarization profile:
#      xcrun notarytool store-credentials pluck-notary \
#          --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>
#
# No secret is ever read by this script — notarytool talks to the keychain itself.
#
#   ./Scripts/release.sh            → .build/Pluck.zip, notarized and stapled
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NOTARY_PROFILE="${NOTARY_PROFILE:-pluck-notary}"
APP="$ROOT/.build/Pluck.app"
ZIP="$ROOT/.build/Pluck.zip"

# Exact-match the certificate rather than letting codesign pick: a machine with both a
# "Development" and a "Developer ID Application" identity will happily sign with the wrong
# one, and the failure only shows up as a Gatekeeper rejection on someone else's Mac.
IDENTITY="${DEVELOPER_ID:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
fi
if [ -z "$IDENTITY" ]; then
    cat >&2 <<'MSG'
No "Developer ID Application" identity in the keychain.

  Xcode ▸ Settings ▸ Accounts ▸ (your team) ▸ Manage Certificates… ▸ + ▸
  Developer ID Application

Then re-run. `security find-identity -v -p codesigning` should list it.
MSG
    exit 1
fi
echo "==> identity: $IDENTITY"

# The identity is handed to bundle.sh rather than applied here afterwards. Sparkle made the
# bundle nested — a framework holding two XPC services, a relaunch helper and a progress app
# — and nested code has to be signed inside out, before its container. Re-signing only the
# outer .app here would leave four pieces bearing sparkle-project's signature inside one
# bearing ours, which `codesign --verify --strict` accepts and Gatekeeper does not.
CODESIGN_IDENTITY="$IDENTITY" "$ROOT/Scripts/bundle.sh" release

# ditto, not zip: it is the only archiver that preserves the bundle's symlinks and
# extended attributes, and notarytool rejects an archive that lost them.
echo "==> submitting for notarization"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

# Stapling writes the ticket into the .app, so the zip has to be rebuilt afterwards —
# shipping the pre-staple archive means every user's first launch needs the network.
echo "==> stapling"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Gatekeeper verdict"
spctl --assess --type execute --verbose=2 "$APP"

echo "==> $ZIP"
shasum -a 256 "$ZIP"

# ---------------------------------------------------------------------------------------
# The appcast: the file Sparkle actually reads, and the second signature on the release.
#
# Notarization proves Apple saw the bundle; the EdDSA signature in the appcast proves *we*
# published this exact zip. They are different claims and Sparkle only checks the second, so
# skipping this step ships an update nobody can verify.
#
# One-time setup on the maintainer's machine, and it is where the private key comes from:
#
#   1. Fetch the Sparkle release matching Package.resolved and run its key generator:
#        ./bin/generate_keys
#      It writes the *private* key into the login keychain (item "Private key for signing
#      Sparkle updates") and prints the public key to the terminal. Nothing lands on disk,
#      and nothing about it belongs in this repository.
#   2. Put the printed public key where bundle.sh looks for it — either
#        export SPARKLE_PUBLIC_ED_KEY='<the printed base64>'
#      or, once and for good, `Packaging/sparkle_public_key.txt` (gitignored). Builds made
#      without it are built with no updater at all, on purpose.
#   3. Back the private key up. It is not recoverable, and losing it means every installed
#      copy of Pluck stops being able to accept an update from us: the only remedy is asking
#      every user to download a new build by hand. `./bin/generate_keys -x <file>` exports it.
#
# `generate_appcast` then signs every zip in a directory and writes the feed. It reads the
# private key from the keychain itself — no secret passes through this script, exactly as
# with notarytool above.
#
# TODO(CI): this is the step that keeps release.sh a laptop script. `generate_appcast` needs
# the private key, which means a CI runner needs it in a secret, which means deciding whether
# that trade is worth making at all — an update-signing key in a hosted runner is a different
# risk from a notarization password. Until that is decided, releases are cut by hand.
APPCAST_DIR="$ROOT/.build/appcast"
SPARKLE_BIN="${SPARKLE_BIN:-}"
if [ -z "$SPARKLE_BIN" ] || [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
    cat <<'MSG'

==> appcast: skipped

Sparkle's tools are not on this machine. To generate and sign the feed:

  1. Download the Sparkle release matching Package.resolved from
     https://github.com/sparkle-project/Sparkle/releases and unpack it.
  2. export SPARKLE_BIN=/path/to/Sparkle-<version>/bin
  3. Re-run this script (the notarized zip is already built and cached).

The release is publishable without it — users just cannot be updated *to* it
automatically until the feed exists.
MSG
    exit 0
fi

echo "==> generating and signing the appcast"
# generate_appcast works on a directory of archives and emits one feed describing all of
# them, so previous releases have to be beside this one or the feed forgets they existed.
# `--download-url-prefix` is what turns local filenames into the GitHub Release URLs the
# feed has to point at; `latest/download/<name>` is the redirect that never goes stale.
mkdir -p "$APPCAST_DIR"
cp "$ZIP" "$APPCAST_DIR/"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/RuochenLyu/pluck/releases/latest/download/" \
    "$APPCAST_DIR"

echo "==> $APPCAST_DIR/appcast.xml"
echo "    attach it, and Pluck.zip, to the GitHub Release"
