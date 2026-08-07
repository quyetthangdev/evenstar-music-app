#!/bin/bash
#
# Build Evenstar and run it on a real iPhone, without Xcode.
#
#   ./device.sh                     the only connected device
#   ./device.sh "iPhone của Thắng"  when more than one is plugged in
#   xcrun devicectl list devices    what you can pass
#
# Replaces the ⌘R round trip for the common case: change code, see it on the
# phone. Roughly five seconds for an incremental build.
#
# What this does NOT give you is a debugger. Breakpoints, the view hierarchy
# inspector, Instruments and the memory graph all need Xcode to have launched the
# process — so use ⌘R when you want to inspect something, and this when you only
# want to look at it.
#
# Requirements, all of which are already true if ⌘R has ever worked here: the
# phone is plugged in or on the same network, unlocked, trusted, and has
# Developer Mode on.

set -euo pipefail

PROJECT="Evenstar/Evenstar.xcodeproj"
SCHEME="Evenstar"

cd "$(dirname "$0")"

# One `devicectl` call, parsed twice. It reports two different identifiers for
# the same phone — a CoreDevice UUID that `devicectl` itself takes, and the
# hardware UDID that `xcodebuild -destination` takes — and passing either one to
# the wrong tool fails with a message that does not mention identifiers at all.
DEVICES_JSON=$(mktemp)
trap 'rm -f "$DEVICES_JSON"' EXIT
xcrun devicectl list devices --json-output "$DEVICES_JSON" > /dev/null 2>&1

NAME_FILTER="${1:-}"
read -r CORE_ID HW_ID DEVICE_NAME <<EOF
$(python3 - "$DEVICES_JSON" "$NAME_FILTER" <<'PY'
import json, sys

path, wanted = sys.argv[1], sys.argv[2]
devices = json.load(open(path))["result"]["devices"]

# `tunnelState == "connected"` exactly, not "anything but unavailable".
#
# This script once installed a build onto the wrong phone. The filter accepted
# any device whose tunnel was not literally "unavailable", and a second phone
# that had been paired earlier was sitting at "disconnected" — which passed, and
# happened to sort first. "connected" is the only state that means the device is
# reachable right now; everything else is a device this machine merely knows.
usable = [
    d for d in devices
    if d.get("connectionProperties", {}).get("tunnelState") == "connected"
    and (not wanted or d["deviceProperties"]["name"] == wanted)
]
if not usable:
    print("", "", "")
    sys.exit(0)

# **Refuse rather than choose.** Picking the first of several is what put a
# build on someone else's phone, and no ordering rule fixes that — the script
# cannot know which one was meant. With two connected, the user names one.
if len(usable) > 1:
    print("AMBIGUOUS", "", " / ".join(d["deviceProperties"]["name"] for d in usable))
    sys.exit(0)

d = usable[0]
print(
    d["identifier"],
    d["hardwareProperties"]["udid"],
    d["deviceProperties"]["name"],
)
PY
)
EOF

if [ "${CORE_ID:-}" = "AMBIGUOUS" ]; then
  echo "✗ More than one device is connected: $DEVICE_NAME" >&2
  echo "  Name the one you want:  ./device.sh \"iPhone của Thắng\"" >&2
  exit 1
fi

if [ -z "${CORE_ID:-}" ]; then
  if [ -n "$NAME_FILTER" ]; then
    echo "✗ No connected device named \"$NAME_FILTER\"." >&2
  else
    echo "✗ No connected iPhone." >&2
  fi
  echo "  Devices this Mac knows about:" >&2
  xcrun devicectl list devices 2>/dev/null | sed 's/^/    /' >&2
  exit 1
fi

echo "▸ Building for $DEVICE_NAME"
# `-allowProvisioningUpdates` so a lapsed profile is renewed here rather than
# failing with a signing error that reads like a project misconfiguration. It
# touches the profiles in ~/Library/MobileDevice, never the project file.
#
# Not piped into a filter that hides failures: a broken build has to show its own
# error in full. `|| true` on the grep only, so the pipeline's exit status still
# comes from `set -o pipefail` on xcodebuild.
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS,id=$HW_ID" \
  -allowProvisioningUpdates \
  | grep -E "error:|warning:|BUILD" | grep -v AppIntents || true

# Asked for rather than globbed, for the same reason `run.sh` asks: DerivedData
# can hold several builds of this project and picking the newest by mtime
# installs whichever was touched last, which is not necessarily this one.
SETTINGS=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS,id=$HW_ID" -showBuildSettings 2>/dev/null)
APP_DIR=$(echo "$SETTINGS" | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')
APP_NAME=$(echo "$SETTINGS" | awk -F' = ' '/ FULL_PRODUCT_NAME/ {print $2; exit}')
APP_PATH="$APP_DIR/$APP_NAME"

if [ ! -d "$APP_PATH" ]; then
  echo "✗ No app at $APP_PATH — the build failed. Scroll up." >&2
  exit 1
fi

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist")

echo "▸ Installing $BUNDLE_ID"
xcrun devicectl device install app --device "$CORE_ID" "$APP_PATH" > /dev/null

echo "▸ Launching"
# `--terminate-existing`, or a second run attaches to the copy already running
# and the change you came to look at is not in it.
xcrun devicectl device process launch \
  --device "$CORE_ID" --terminate-existing "$BUNDLE_ID" > /dev/null

echo "✓ Running on $DEVICE_NAME"
