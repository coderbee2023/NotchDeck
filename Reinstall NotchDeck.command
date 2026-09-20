#!/bin/zsh
# Clean reinstall of NotchDeck: remove every copy, build fresh, install to /Applications.
# Builds Debug on purpose — the debug bridge lives only in Debug builds and is what lets
# Claude test and screenshot while bugs are open. Switch CONFIG to Release when shipping.
set -u
CONFIG=Debug
LOG=~/Projects/NotchDeck/reinstall.log
exec > >(tee "$LOG") 2>&1
echo "=== NotchDeck clean reinstall ($CONFIG)  $(date) ==="

echo "--- existing copies:"
/usr/bin/mdfind "kMDItemCFBundleIdentifier == tn.wassim.NotchDeck" || true
ls -d /Applications/NotchDeck.app ~/Applications/NotchDeck.app 2>/dev/null || true

echo "--- quitting running instances"
osascript -e 'tell application "NotchDeck" to quit' 2>/dev/null || true
sleep 1
pkill -f "NotchDeck.app/Contents/MacOS/NotchDeck" 2>/dev/null || true
sleep 1

echo "--- removing old copies"
rm -rf /Applications/NotchDeck.app
rm -rf ~/Applications/NotchDeck.app
rm -rf ~/Projects/NotchDeck/build/Debug/NotchDeck.app
rm -rf ~/Projects/NotchDeck/build/Release/NotchDeck.app

echo "--- building $CONFIG"
cd ~/Projects/NotchDeck
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck -configuration "$CONFIG" \
  SYMROOT="$PWD/build" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build 2>&1 | tail -25

if [ ! -d "build/$CONFIG/NotchDeck.app" ]; then
  echo "BUILD FAILED - nothing installed, old copies are gone"
  exit 1
fi

echo "--- installing to /Applications"
cp -R "build/$CONFIG/NotchDeck.app" /Applications/
xattr -dr com.apple.quarantine /Applications/NotchDeck.app 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/NotchDeck.app 2>/dev/null || true

echo "--- launching"
open /Applications/NotchDeck.app
sleep 3

echo "--- final state:"
/usr/bin/mdfind "kMDItemCFBundleIdentifier == tn.wassim.NotchDeck" || true
codesign -dv /Applications/NotchDeck.app 2>&1 | head -3
ps aux | grep "[N]otchDeck.app/Contents/MacOS/NotchDeck" | awk '{print "running pid", $2}'
echo "=== done ==="
