#!/bin/zsh
# Usage: build-release.sh [notarize]
set -e
cd ~/Projects/NotchDeck
exec > ~/Projects/NotchDeck/build-release.log 2>&1
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/Release/NotchDeck.app/Contents/Info.plist 2>/dev/null || echo "1.0.0")
DEVID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
if [ -n "$DEVID" ]; then IDENT="$DEVID"; TEAM=$(echo "$DEVID" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/'); else IDENT="Apple Development"; TEAM=95UFXX6BX5; fi
echo "Team: $TEAM"
echo "Signing identity: $IDENT"
rm -rf build/Release dist
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck -configuration Release build \
  CODE_SIGN_IDENTITY="$IDENT" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  > build-release-xcode.log 2>&1
echo "xcodebuild exit $?"
APP=build/Release/NotchDeck.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $APP/Contents/Info.plist)
codesign --verify --deep --strict --verbose=2 $APP
codesign -d --entitlements :- $APP | head -20
mkdir -p dist/dmg
cp -R $APP dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname "NotchDeck" -srcfolder dist/dmg -ov -format UDZO "dist/NotchDeck-$VERSION.dmg"
rm -rf dist/dmg
if [ -n "$DEVID" ]; then codesign --sign "$IDENT" --timestamp "dist/NotchDeck-$VERSION.dmg"; fi
(cd build/Release && ditto -c -k --keepParent NotchDeck.app "../../dist/NotchDeck-$VERSION.zip")
ls -la dist
if [ "$1" = "notarize" ] && [ -n "$DEVID" ]; then
  xcrun notarytool submit "dist/NotchDeck-$VERSION.dmg" --keychain-profile "notchdeck" --wait
  xcrun stapler staple "dist/NotchDeck-$VERSION.dmg"
  spctl -a -t open --context context:primary-signature -v "dist/NotchDeck-$VERSION.dmg"
fi
echo "DONE"
