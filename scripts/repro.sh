#!/usr/bin/env bash
#
# Makes the race visible by delaying the "ActivityManager" handler thread of system_server.
#
# That thread runs ServiceRecord.postNotification(), the place where Android looks up the
# notification channel of a foreground service notification. startForeground() returns before
# that lookup happens. On an idle emulator the lookup follows within about a millisecond, so the
# app never loses the race. This script freezes the thread for 150 ms at a time, which is what a
# busy device does to it now and then.
#
# Needs: a rooted emulator (a "Google APIs" system image, not "Google Play"), the debug build of
# this app installed, and Metro running (`npm start`, `adb reverse tcp:8081 tcp:8081`).
#
# Usage: scripts/repro.sh [seconds to wait for the crash, default 30]

set -u
PKG=com.rnvchannelrepro
TIMEOUT="${1:-30}"

adb root >/dev/null 2>&1
adb wait-for-device
if [ "$(adb shell id -u | tr -d '\r')" != "0" ]; then
  echo "adb is not root. Use an emulator with a \"Google APIs\" system image." >&2
  exit 2
fi

SYSTEM_SERVER=$(adb shell pidof system_server | tr -d '\r')
# system_server has four threads whose name starts with "ActivityManager" (the kernel cuts the
# names to 15 characters). The handler thread is created first, so it has the lowest tid.
TID=$(adb shell "ps -T -p $SYSTEM_SERVER" | awk '$NF == "ActivityManager" { print $3 }' | sort -n | head -1)
if [ -z "$TID" ]; then
  echo "Could not find the ActivityManager thread of system_server." >&2
  exit 2
fi
echo "system_server pid $SYSTEM_SERVER, ActivityManager handler thread tid $TID"

# A cgroup v1 freezer can freeze a single thread.
adb shell "mkdir -p /dev/rnv_freezer && (grep -q ' /dev/rnv_freezer ' /proc/mounts || mount -t cgroup -o freezer none /dev/rnv_freezer) && mkdir -p /dev/rnv_freezer/am && echo $TID > /dev/rnv_freezer/am/tasks"
STATE=/dev/rnv_freezer/am/freezer.state

thaw() {
  adb shell "echo THAWED > $STATE"
}
trap 'kill "${FREEZER_PID:-}" 2>/dev/null; thaw' EXIT

adb shell am force-stop "$PKG"
thaw
adb logcat -b all -c
adb shell am start -n "$PKG/.MainActivity" >/dev/null
echo "Waiting 8 s for the app to load its bundle and start mounting/unmounting <Video>..."
sleep 8

adb shell "while true; do echo FROZEN > $STATE; sleep 0.15; echo THAWED > $STATE; sleep 0.06; done" >/dev/null 2>&1 &
FREEZER_PID=$!

START=$(date +%s)
RESULT="no crash in ${TIMEOUT} s"
while [ $(( $(date +%s) - START )) -lt "$TIMEOUT" ]; do
  if adb logcat -d -b crash | grep -q "Bad notification for startForeground"; then
    RESULT="CRASH after $(( $(date +%s) - START )) s"
    break
  fi
  sleep 1
done

kill "$FREEZER_PID" 2>/dev/null
thaw

STARTS=$(adb logcat -d -b events | grep "notification_enqueue" | grep "$PKG" | grep -c ",9999,")
echo
echo "Result: $RESULT (service start commands seen: $STARTS)"
echo
adb logcat -d -b system,crash -v time | grep -E "Error showing notification for service|invalid channel for service notification|ServiceRecord\\\$1.run|FATAL EXCEPTION|Bad notification for startForeground" | head -8
