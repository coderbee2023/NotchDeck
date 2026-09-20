#!/bin/zsh
# Build Debug and replace the installed copy in /Applications, so there is only ever
# one NotchDeck on the system and it is the one being tested.
exec > ~/Projects/NotchDeck/build-run.log 2>&1
cd ~/Projects/NotchDeck
PIDS=$(/bin/ps aux | grep "[N]otchDeck.app/Contents/MacOS/NotchDeck" | awk '{print $2}')
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck -configuration Debug SYMROOT="$PWD/build" build > build-debug.log 2>&1
RC=$?
echo "build exit $RC"
[ $RC -ne 0 ] && exit $RC
for p in ${(f)PIDS}; do /bin/kill -9 $p; done
sleep 1
/bin/rm -rf /Applications/NotchDeck.app
/bin/cp -R build/Debug/NotchDeck.app /Applications/
/usr/bin/xattr -dr com.apple.quarantine /Applications/NotchDeck.app 2>/dev/null
/usr/bin/open /Applications/NotchDeck.app
echo "installed and launched from /Applications"
