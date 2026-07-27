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

"$ROOT/Scripts/bundle.sh" release

# `--options runtime` is what notarization requires; `--timestamp` is what keeps the
# signature valid after the certificate itself expires.
echo "==> signing for distribution"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

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
