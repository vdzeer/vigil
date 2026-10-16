#!/bin/zsh
# Build Vigil.app, put it in ~/Applications and start it.
#
#   scripts/build-app.sh              build, install, start
#   scripts/build-app.sh --no-start   build and install only
#   scripts/build-app.sh --no-install build into build/Vigil.app only
#
# Signing: ad hoc by default, which is all a copy for your own Mac needs. Set SIGN_IDENTITY to
# a certificate name to sign with it and the hardened runtime, as releases are; a "Developer ID
# Application" identity also adds a secure timestamp, as notarization requires (scripts/release.sh).

set -euo pipefail

ROOT="${0:A:h:h}"
NAME="Vigil"
BUILD="$ROOT/build"
APP="$BUILD/$NAME.app"
DEST="$HOME/Applications/$NAME.app"
MODE="${1:-}"
IDENTITY="${SIGN_IDENTITY:--}"

cd "$ROOT"
# One binary for Apple silicon and Intel Macs.
swift build -c release --arch arm64 --arch x86_64 --product "$NAME"
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/$NAME" "$APP/Contents/MacOS/$NAME"
# Libraries load from the bundle only: the build adds search paths such as the toolchain folder
# of the Mac it was built on, and a library planted there would load into the app.
EXE="$APP/Contents/MacOS/$NAME"
for rpath in ${(u)${(f)"$(otool -l "$EXE" | awk '/LC_RPATH/ { getline; getline; print $2 }')"}}; do
  install_name_tool -delete_rpath "$rpath" "$EXE"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXE"
# Sparkle, for updates. Vigil is not sandboxed, so Sparkle's XPC services are left out.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN/Sparkle.framework" "$SPARKLE"
rm -rf "$SPARKLE/XPCServices" "$SPARKLE/Versions/B/XPCServices"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/allow-lid-closed.sh" "$APP/Contents/Resources/"
chmod 755 "$APP/Contents/Resources/allow-lid-closed.sh"

rm -rf "$BUILD/AppIcon.iconset"
"$APP/Contents/MacOS/$NAME" --make-iconset "$BUILD/AppIcon.iconset"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$BUILD/AppIcon.iconset"

sign() {
  if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$1"
  elif [[ "$IDENTITY" == "Developer ID Application:"* ]]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$1"
  else
    codesign --force --options runtime --sign "$IDENTITY" "$1"
  fi
}
# Inside out, never --deep: Sparkle's helpers, Sparkle, then the app.
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign "$APP"
codesign --verify --strict --deep "$APP"

[[ "$MODE" == "--no-install" ]] && { echo "Built: $APP"; exit 0; }

# Vigil treats a plain kill like Quit: it switches lid-closed mode off first. The new copy
# puts it back.
if pgrep -xq "$NAME"; then
  pkill -x "$NAME" || true
  for _ in {1..50}; do pgrep -xq "$NAME" || break; sleep 0.1; done
fi

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "Installed: $DEST"

if [[ "$MODE" != "--no-start" ]]; then
  open "$DEST"
  echo "Started. Look for the eye in the menu bar."
fi
