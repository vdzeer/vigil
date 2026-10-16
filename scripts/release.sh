#!/bin/zsh
# Make the disk image for a GitHub release: signed with Developer ID, notarized by Apple and
# stapled, so it opens on any Mac without a warning.
#
#   scripts/release.sh           build/Vigil-<version>.dmg and build/appcast.xml
#   scripts/release.sh --check   only check that signing, notarization and the update key are set up
#
# Attach both files to a GitHub release tagged v<version>: installed copies read appcast.xml from
# the latest release and update themselves (Sparkle). Raise CFBundleShortVersionString and
# CFBundleVersion in Resources/Info.plist together before a release; they must be equal.
#
# Needs, once per Mac:
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode → Settings → Accounts → your team → Manage Certificates → + → Developer ID Application).
#   2. A notarytool profile in the keychain; the default name is "notary" (or set NOTARY_PROFILE):
#        xcrun notarytool store-credentials notary --apple-id <Apple ID> --team-id <team ID>
#      It asks for an app-specific password from account.apple.com.
#   3. The update signing key in the login keychain, the one whose public half is SUPublicEDKey in
#      Info.plist. Made once with .build/artifacts/sparkle/Sparkle/bin/generate_keys; keep a copy
#      (generate_keys -x <file>) somewhere safe: without it no update can reach installed copies.

set -euo pipefail

ROOT="${0:A:h:h}"
NAME="Vigil"
REPO="https://github.com/vdzeer/vigil"
PROFILE="${NOTARY_PROFILE:-notary}"
PLIST="Resources/Info.plist"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
cd "$ROOT"
swift package resolve >/dev/null

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)}"
problems=()
[[ "$IDENTITY" == "Developer ID Application:"* ]] \
  || problems+=("No \"Developer ID Application\" certificate in the keychain.")
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || problems+=("No notarytool profile named \"$PROFILE\" (see the top of this script).")
[[ "$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null)" == "$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$PLIST")" ]] \
  || problems+=("The update signing key in the keychain does not match SUPublicEDKey in $PLIST.")
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")" \
  == "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")" ]] \
  || problems+=("CFBundleShortVersionString and CFBundleVersion in $PLIST differ.")
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
[[ "$VERSION" =~ '^[0-9]+(\.[0-9]+)*$' ]] || { echo "Odd version: $VERSION" >&2; exit 1; }
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

# The update feed: one item, this version. Sparkle checks the EdDSA signature before installing.
SIGNATURE="$("$SPARKLE_BIN/sign_update" "$DMG")"
MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
cat > build/appcast.xml <<FEED
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$NAME</title>
    <item>
      <title>$NAME $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$REPO/releases/tag/v$VERSION</sparkle:fullReleaseNotesLink>
      <enclosure url="$REPO/releases/download/v$VERSION/$NAME-$VERSION.dmg" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
FEED
# The feed itself is signed too (SURequireSignedFeed): sign_update embeds the signature in it.
"$SPARKLE_BIN/sign_update" build/appcast.xml

echo "Release: $ROOT/$DMG and $ROOT/build/appcast.xml"
echo "Publish: gh release create v$VERSION $DMG build/appcast.xml"
shasum -a 256 "$DMG"
