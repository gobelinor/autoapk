#!/usr/bin/env bash
set -e

APPNAME=$1

if [[ -z "$APPNAME" ]]; then
  echo "Usage: $0 <appname>"
  exit 1
fi

if ! adb get-state >/dev/null; then
  echo "Aucun device ADB prêt."
  exit 1
fi

PACKAGE=$(adb shell pm list packages | grep "$APPNAME" | sed 's/package://')

if [ -z "$PACKAGE" ]; then
  echo "App '$APPNAME' not found on the device."
  exit 1
fi

if [[ $(echo "$PACKAGE" | wc -l) -gt 1 ]]; then
  echo "Multiple packages found for '$APPNAME':"
  echo "$PACKAGE" | sed 's/package://'
  echo "Please specify a more precise app name."
  exit 1
fi

APKSDIR="./apks"
mkdir -p "$APKSDIR"

MATCHES=()

while IFS= read -r line; do
  MATCHES+=("$line")
done < <(adb shell pm path $PACKAGE | sed 's/package://')

cd "$APKSDIR"

for i in "${!MATCHES[@]}"; do
  adb pull "${MATCHES[$i]}" 
done
echo "APK(s) pulled to $APKSDIR"

cd - >/dev/null

echo "Done."
exit 0
