#!/bin/bash
# Baut Sky Reader.app (Apple Silicon), ad-hoc signiert, und packt ZIP + DMG nach dist/.
# Aufruf: Scripts/build_app.sh [BUILDNUMMER]
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(tr -d ' \n' < VERSION)"
BUILD="${1:-1}"
APP="dist/Sky Reader.app"
echo "==> Sky Reader $VERSION (Build $BUILD)"

swift build -c release --arch arm64 --product SkyReader
BIN="$(swift build -c release --arch arm64 --show-bin-path)/SkyReader"

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SkyReader"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp -R Resources/Catalogs "$APP/Contents/Resources/Catalogs"
cp -R Resources/Images "$APP/Contents/Resources/Images"

# App-Icon (.icns) aus 1024er PNG
ICONSET="dist/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2)); sips -z $d $d Resources/AppIcon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Ad-hoc-Signatur (kein Developer-Zertifikat)
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

# Pakete
( cd dist && ditto -c -k --sequesterRsrc --keepParent "Sky Reader.app" "SkyReader-$VERSION.zip" )
STAGE="dist/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Programme"
hdiutil create -volname "Sky Reader $VERSION" -srcfolder "$STAGE" -ov -format UDZO "dist/SkyReader-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"
ls -la dist
