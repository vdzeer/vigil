#!/bin/zsh
# Make the disk image for a GitHub release: signed with Developer ID, notarized by Apple and
# stapled, so it opens on any Mac without a warning.
#
#   scripts/release.sh           build/Vigil-<version>.dmg
#   scripts/release.sh --check   only check that signing and notarization are set up
#
# Needs, once per Mac:
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode → Settings → Accounts → your team → Manage Certificates → + → Developer ID Application).
#   2. A notarytool profile in the keychain; the default name is "notary" (or set NOTARY_PROFILE):
#        xcrun notarytool store-credentials notary --apple-id <Apple ID> --team-id <team ID>
#      It asks for an app-specific password from account.apple.com.

set -euo pipefail

ROOT="${0:A:h:h}"
NAME="Vigil"
PROFILE="${NOTARY_PROFILE:-notary}"
cd "$ROOT"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)}"
problems=()
[[ "$IDENTITY" == "Developer ID Application:"* ]] \
  || problems+=("No \"Developer ID Application\" certificate in the keychain.")
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || problems+=("No notarytool profile named \"$PROFILE\" (see the top of this script).")
if (( ${#problems} )); then
  printf '%s\n' "${problems[@]}" >&2
  exit 1
fi
if [[ "${1:-}" == "--check" ]]; then
  echo "Ready to release: $IDENTITY, notary profile \"$PROFILE\"."
  exit 0
fi

SIGN_IDENTITY="$IDENTITY" scripts/build-app.sh --no-install
APP="build/$NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/$NAME-$VERSION.dmg"

STAGE="build/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"

codesign --force --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo "Release: $ROOT/$DMG"
shasum -a 256 "$DMG"
