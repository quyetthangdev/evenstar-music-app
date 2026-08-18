#!/bin/bash
#
# Build Evenstar and run it on a simulator.
#
#   ./run.sh                              iPhone 17
#   ./run.sh "iPhone SE (3rd generation)" any other simulator
#   xcrun simctl list devices available   what you can pass
#
# For a real device use ./device.sh, which does the same thing over USB. The
# drag, the lock screen and landscape safe-area insets are all things a simulator
# cannot answer, so most visual checks belong there rather than here.
#
# Xcode and ⌘R remain the only way to get a debugger attached — breakpoints, the
# view hierarchy inspector, Instruments.
#
# Tip: drag .mp3 files from Finder onto the Simulator window. They land in the
# Files app, and the + button in Evenstar imports them. Most of the app is
# untestable without a library, and this is the cheapest way to get one.

set -euo pipefail

DEVICE="${1:-iPhone 17}"
PROJECT="Evenstar/Evenstar.xcodeproj"
SCHEME="Evenstar"
DESTINATION="platform=iOS Simulator,name=$DEVICE"

cd "$(dirname "$0")"

# Checked before anything else, because the failure otherwise is awful: the
# build prints its entire list of available destinations, then the script exits
# silently on the next command substitution, and the user is left with a wall of
# device names and no sentence telling them what went wrong.
if ! xcrun simctl list devices available | grep -qF "$DEVICE ("; then
  echo "✗ No simulator named \"$DEVICE\"." >&2
  echo "  Available:" >&2
  xcrun simctl list devices available \
    | grep -E "^\s+\w.*\(" | sed -E 's/ \([0-9A-F-]+\).*//; s/^ */    /' >&2
  exit 1
fi

echo "▸ Building for $DEVICE"
# Not piped into grep: a failure has to show its own error, in full. Filtering
# the log to look tidy is how a broken build gets mistaken for a passing one.
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
  | grep -E "error:|warning:|BUILD" | grep -v AppIntents || true

# `xcodebuild` reports the paths itself rather than us globbing DerivedData —
# that directory can hold several builds of the same project, and picking the
# newest by mtime silently installs whichever one happened to be touched last.
SETTINGS=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -showBuildSettings 2>/dev/null)
APP_DIR=$(echo "$SETTINGS" | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')
APP_NAME=$(echo "$SETTINGS" | awk -F' = ' '/ FULL_PRODUCT_NAME/ {print $2; exit}')
APP_PATH="$APP_DIR/$APP_NAME"

if [ ! -d "$APP_PATH" ]; then
  echo "✗ No app at $APP_PATH — the build failed. Scroll up." >&2
  exit 1
fi

# Read from the built app rather than hard-coding. The bundle id here is
# com.evenstar.app while the target is named Evenstar, which is exactly the sort
# of guess that fails with a "request to open failed" and no explanation.
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist")

echo "▸ Booting $DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
# `simctl` only drives the simulator; without this there is no window to watch.
open -a Simulator
xcrun simctl bootstatus "$DEVICE" -b > /dev/null 2>&1 || true

echo "▸ Installing $BUNDLE_ID"
xcrun simctl install booted "$APP_PATH"

echo "▸ Launching"
xcrun simctl launch booted "$BUNDLE_ID" > /dev/null

echo "✓ Running on $DEVICE"
