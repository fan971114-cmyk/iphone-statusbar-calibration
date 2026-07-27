#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$ROOT/artifacts"
mkdir -p "$ARTIFACTS"
mkdir -p \
  "$ARTIFACTS/metadata" \
  "$ARTIFACTS/previews" \
  "$ARTIFACTS/time" \
  "$ARTIFACTS/battery" \
  "$ARTIFACTS/icons"

APP_DIR="$(bash "$ROOT/scripts/build-probe-app.sh")"

UDID="$(
  xcrun simctl list -j devices available | python3 -c '
import json
import re
import sys

data = json.load(sys.stdin)
candidates = []
for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = tuple(map(int, match.groups()))
    for device in devices:
        if device.get("isAvailable") and device.get("name") == "iPhone 17 Pro":
            candidates.append((version, device["udid"]))
if not candidates:
    raise SystemExit("No available iPhone 17 Pro simulator was found")
print(sorted(candidates)[-1][1])
'
)"

echo "$UDID" | tee "$ARTIFACTS/metadata/simulator-udid.txt"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

# Match the user's Chinese-region iPhone and force the system status bar to use
# 24-hour time. The disposable simulator must reboot after these writes so
# SpringBoard reloads both the locale and battery-percentage preferences.
xcrun simctl spawn "$UDID" defaults write NSGlobalDomain AppleLocale -string "zh_CN"
xcrun simctl spawn "$UDID" defaults write NSGlobalDomain AppleLanguages -array "zh-Hans-CN"
xcrun simctl spawn "$UDID" defaults write NSGlobalDomain AppleICUForce24HourTime -bool true
xcrun simctl spawn "$UDID" defaults write com.apple.control-center BatteryShowPercentage -bool true || true
xcrun simctl spawn "$UDID" defaults write com.apple.springboard SBShowBatteryPercentage -bool true || true
xcrun simctl spawn "$UDID" defaults write com.apple.springboard ShowBatteryPercentage -bool true || true

xcrun simctl shutdown "$UDID"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b

{
  echo "AppleLocale:"
  xcrun simctl spawn "$UDID" defaults read NSGlobalDomain AppleLocale || true
  echo "AppleLanguages:"
  xcrun simctl spawn "$UDID" defaults read NSGlobalDomain AppleLanguages || true
  echo "AppleICUForce24HourTime:"
  xcrun simctl spawn "$UDID" defaults read NSGlobalDomain AppleICUForce24HourTime || true
  echo "BatteryShowPercentage:"
  xcrun simctl spawn "$UDID" defaults read com.apple.control-center BatteryShowPercentage || true
  echo "SBShowBatteryPercentage:"
  xcrun simctl spawn "$UDID" defaults read com.apple.springboard SBShowBatteryPercentage || true
  echo "ShowBatteryPercentage:"
  xcrun simctl spawn "$UDID" defaults read com.apple.springboard ShowBatteryPercentage || true
} > "$ARTIFACTS/status-preferences.txt" 2>&1

CROP_TOOL="$ARTIFACTS/metadata/crop-png"
swiftc "$ROOT/scripts/crop-png.swift" -o "$CROP_TOOL"

# Capture the unmodified SpringBoard status bar before applying any override.
# This is only a control sample; do not launch Settings here because iOS may
# keep a back-to-Settings breadcrumb in the next app's status bar.
xcrun simctl status_bar "$UDID" clear
sleep 1
xcrun simctl io "$UDID" screenshot "$ARTIFACTS/previews/baseline-springboard.png"

xcrun simctl install "$UDID" "$APP_DIR"
xcrun simctl launch "$UDID" com.codex.statusbarprobe
sleep 2

capture_named_sample() {
  local name="$1"
  shift
  local output="$ARTIFACTS/previews/full-${name}.png"

  xcrun simctl status_bar "$UDID" clear
  xcrun simctl status_bar "$UDID" override "$@"
  xcrun simctl status_bar "$UDID" list > "$ARTIFACTS/metadata/status-list-${name}.txt" 2>&1 || true
  sleep 2
  xcrun simctl io "$UDID" screenshot "$output"
  sips -g pixelWidth -g pixelHeight "$output" >> "$ARTIFACTS/metadata/image-dimensions.txt"
  "$CROP_TOOL" "$output" "$ARTIFACTS/previews/crop-time-${name}.png" 145 35 190 95
  "$CROP_TOOL" "$output" "$ARTIFACTS/icons/signal-full.png" 850 45 90 80
  "$CROP_TOOL" "$output" "$ARTIFACTS/icons/wifi-full.png" 930 45 90 80
  "$CROP_TOOL" "$output" "$ARTIFACTS/previews/crop-battery-${name}.png" 1005 45 130 80
  "$CROP_TOOL" "$output" "$ARTIFACTS/previews/crop-right-${name}.png" 835 40 315 95
}

COMMON_STATUS_ARGS=(
  --time "19:26"
  --cellularMode active
  --cellularBars 4
  --wifiMode active
  --wifiBars 3
)

capture_named_sample "project-a-preview-19-26-battery-46" \
  "${COMMON_STATUS_ARGS[@]}" \
  --batteryState discharging \
  --batteryLevel 46

TMP_SCREEN="$ARTIFACTS/metadata/tmp-full.png"
SETTLE_SECONDS="${STATUS_POOL_SETTLE_SECONDS:-0.35}"

capture_crop() {
  local output="$1"
  local x="$2"
  local y="$3"
  local width="$4"
  local height="$5"

  xcrun simctl io "$UDID" screenshot "$TMP_SCREEN" >/dev/null
  "$CROP_TOOL" "$TMP_SCREEN" "$output" "$x" "$y" "$width" "$height"
}

echo "Capturing Project A time crops: 11:00-23:59" | tee "$ARTIFACTS/metadata/time-capture-log.txt"
for hour in $(seq 11 23); do
  for minute in $(seq 0 59); do
    label="$(printf "%02d:%02d" "$hour" "$minute")"
    # This simctl build rejects exact HH:00 strings. The user's batch rule
    # permits a 3-minute status-bar time tolerance, so map HH:00 to HH:01.
    override_time="$label"
    if [[ "$minute" -eq 0 ]]; then
      override_time="$(printf "%02d:01" "$hour")"
    fi
    name="$(printf "time-%02d%02d.png" "$hour" "$minute")"
    if ! xcrun simctl status_bar "$UDID" override \
      --time "$override_time" \
      --cellularMode active \
      --cellularBars 4 \
      --wifiMode active \
      --wifiBars 3 \
      --batteryState discharging \
      --batteryLevel 46; then
      echo "$label failed with override $override_time" >> "$ARTIFACTS/metadata/time-capture-failures.txt"
      continue
    fi
    sleep "$SETTLE_SECONDS"
    capture_crop "$ARTIFACTS/time/$name" 145 35 190 95
    echo "$label actual=$override_time $name" >> "$ARTIFACTS/metadata/time-capture-log.txt"
  done
done

echo "Capturing Project A battery crops: 0-100" | tee "$ARTIFACTS/metadata/battery-capture-log.txt"
for level in $(seq 0 100); do
  name="$(printf "battery-%03d.png" "$level")"
  xcrun simctl status_bar "$UDID" override \
    --time "19:26" \
    --cellularMode active \
    --cellularBars 4 \
    --wifiMode active \
    --wifiBars 3 \
    --batteryState discharging \
    --batteryLevel "$level"
  sleep "$SETTLE_SECONDS"
  capture_crop "$ARTIFACTS/battery/$name" 1005 45 130 80
  echo "$level $name" >> "$ARTIFACTS/metadata/battery-capture-log.txt"
done

rm -f "$TMP_SCREEN"

cat > "$ARTIFACTS/manifest.json" <<'JSON'
{
  "project": "A",
  "device": "iPhone 17 Pro",
  "background": "#EDEDED",
  "coordinateSpace": {
    "width": 1206,
    "height": 2622
  },
  "time": {
    "range": "11:00-23:59",
    "count": 780,
    "tolerance": "Target HH:00 crops use the real HH:01 simulator crop because this simctl build rejects exact HH:00 override strings.",
    "crop": {
      "x": 145,
      "y": 35,
      "width": 190,
      "height": 95
    }
  },
  "battery": {
    "range": "0-100",
    "count": 101,
    "crop": {
      "x": 1005,
      "y": 45,
      "width": 130,
      "height": 80
    },
    "sourceRule": "Use the exact simulator crop for each level; do not redraw digits or fill."
  },
  "icons": {
    "signal": "always full",
    "wifi": "captured full, tool may show or hide later",
    "silent": "not captured by simctl status_bar in this workflow"
  }
}
JSON

xcrun simctl status_bar "$UDID" clear
xcrun simctl shutdown "$UDID"
