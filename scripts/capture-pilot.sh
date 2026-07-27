#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$ROOT/artifacts"
mkdir -p "$ARTIFACTS"

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

echo "$UDID" | tee "$ARTIFACTS/simulator-udid.txt"
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

# Capture the unmodified SpringBoard status bar before applying any override.
# This is only a control sample; do not launch Settings here because iOS may
# keep a back-to-Settings breadcrumb in the next app's status bar.
xcrun simctl status_bar "$UDID" clear
sleep 1
xcrun simctl io "$UDID" screenshot "$ARTIFACTS/baseline-springboard.png"

xcrun simctl install "$UDID" "$APP_DIR"
xcrun simctl launch "$UDID" com.codex.statusbarprobe
sleep 2

capture_named_sample() {
  local name="$1"
  shift
  local output="$ARTIFACTS/full-${name}.png"

  xcrun simctl status_bar "$UDID" clear
  xcrun simctl status_bar "$UDID" override "$@"
  xcrun simctl status_bar "$UDID" list > "$ARTIFACTS/status-list-${name}.txt" 2>&1 || true
  sleep 2
  xcrun simctl io "$UDID" screenshot "$output"
  sips -g pixelWidth -g pixelHeight "$output" >> "$ARTIFACTS/image-dimensions.txt"
  swift "$ROOT/scripts/crop-png.swift" "$output" "$ARTIFACTS/crop-time-${name}.png" 120 35 220 95
  swift "$ROOT/scripts/crop-png.swift" "$output" "$ARTIFACTS/crop-signal-${name}.png" 850 45 90 80
  swift "$ROOT/scripts/crop-png.swift" "$output" "$ARTIFACTS/crop-wifi-${name}.png" 930 45 90 80
  swift "$ROOT/scripts/crop-png.swift" "$output" "$ARTIFACTS/crop-battery-${name}.png" 1005 45 130 80
  swift "$ROOT/scripts/crop-png.swift" "$output" "$ARTIFACTS/crop-right-${name}.png" 835 40 315 95
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

xcrun simctl status_bar "$UDID" clear
xcrun simctl shutdown "$UDID"
