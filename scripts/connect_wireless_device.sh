#!/usr/bin/env zsh
set -euo pipefail

# Connect an Android device over adb (wireless)
# Works reliably when run from a login shell or cron by ensuring adb is found

ADB_BIN=$(command -v adb || true)
if [[ -z "$ADB_BIN" ]]; then
  echo "adb not found in PATH. Please ensure Android platform-tools are installed and in your PATH."
  echo "Current PATH: $PATH"
  exit 1
fi

echo "Using adb: $ADB_BIN"

echo "Killing and starting adb server..."
"$ADB_BIN" kill-server
"$ADB_BIN" start-server

echo "Listing devices..."
"$ADB_BIN" devices -l

DEVICE_SHORT_ID=RR8N406QQSW
# Get the device IP (wlan0) while still connected via USB. If empty, print diagnostics and exit.
IP=$("$ADB_BIN" -s "$DEVICE_SHORT_ID" shell ip -f inet addr show wlan0 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)

if [[ -z "$IP" ]]; then
  echo "Failed to detect device IP from adb shell (wlan0)."
  echo "Showing 'ip addr' output for diagnostics:"
  "$ADB_BIN" -s "$DEVICE_SHORT_ID" shell ip addr || true
  echo "Please ensure device is connected and has an active Wi-Fi interface (wlan0)."
  exit 1
fi

echo "Switching device $DEVICE_SHORT_ID to TCP/IP mode on port 5555..."
"$ADB_BIN" -s "$DEVICE_SHORT_ID" tcpip 5555
sleep 1

if [[ -z "$IP" ]]; then
  echo "Failed to detect device IP from adb shell (wlan0)."
  echo "Trying fallback: using adb reverse shell and network interface listing."
  # show diagnostics
  "$ADB_BIN" -s "$DEVICE_SHORT_ID" shell ip -f inet addr show || true
  echo "Please ensure device is connected and the device id ($DEVICE_SHORT_ID) is correct."
  exit 1
fi

echo "Connecting to device at ${IP}:5555..."
"$ADB_BIN" connect "${IP}:5555" || true
sleep 1

echo "Listing connected devices:"
"$ADB_BIN" devices

echo "Done."
# adb kill-server
# adb start-server
# adb devices -l
# adb -s RR8N406QQSW tcpip 5555
# IP=$(adb -s RR8N406QQSW shell ip -f inet addr show wlan0 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
# adb connect "$IP:5555"
# adb devices