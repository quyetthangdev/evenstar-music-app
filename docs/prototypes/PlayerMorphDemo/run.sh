#!/bin/bash
#
# Chạy prototype morph trên simulator.
#
#   ./run.sh                 iPhone 17
#   ./run.sh "iPhone 16e"    simulator khác
#   ./run.sh "iPhone 17" -expanded    mở sẵn full player (để chụp màn hình)
#
# Cùng hình dạng với ./run.sh ở gốc repo, để không phải nhớ hai bộ lệnh.
#
# Muốn xem cho ra cảm giác thật thì mở bằng Xcode và ⌘R trên máy thật —
# simulator dựng hình bằng đường khác, đánh giá độ mượt ở đây là vô nghĩa.
# Simulator dùng để xem *hình*, máy thật để xem *chuyển động*.

set -euo pipefail

DEVICE="${1:-iPhone 17}"
EXTRA_ARG="${2:-}"
PROJECT="PlayerMorphDemo.xcodeproj"
SCHEME="PlayerMorphDemo"
DESTINATION="platform=iOS Simulator,name=$DEVICE"

cd "$(dirname "$0")"

if ! xcrun simctl list devices available | grep -qF "$DEVICE ("; then
  echo "✗ Không có simulator tên \"$DEVICE\"." >&2
  xcrun simctl list devices available | grep -E "^\s+\w.*\(" | sed -E 's/ \([0-9A-F-]+\).*//; s/^ */    /' >&2
  exit 1
fi

echo "▸ Build"
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
  | grep -E "error:|BUILD" || true

SETTINGS=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -showBuildSettings 2>/dev/null)
APP_DIR=$(echo "$SETTINGS" | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')
APP_NAME=$(echo "$SETTINGS" | awk -F' = ' '/ FULL_PRODUCT_NAME/ {print $2; exit}')
APP_PATH="$APP_DIR/$APP_NAME"

if [ ! -d "$APP_PATH" ]; then
  echo "✗ Không thấy app ở $APP_PATH — build hỏng, cuộn lên xem." >&2
  exit 1
fi

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist")

echo "▸ Boot $DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$DEVICE" -b > /dev/null 2>&1 || true

echo "▸ Cài $BUNDLE_ID"
xcrun simctl install booted "$APP_PATH"

echo "▸ Chạy"
if [ -n "$EXTRA_ARG" ]; then
  xcrun simctl launch booted "$BUNDLE_ID" "$EXTRA_ARG" > /dev/null
else
  xcrun simctl launch booted "$BUNDLE_ID" > /dev/null
fi

echo "✓ Đang chạy trên $DEVICE"
