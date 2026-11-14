#!/bin/bash
# Used by .github/workflows/build.yml after a successful Simulator build.
# Boots the newest iPhone Pro Max simulator, installs the app, opens each
# screen with `-screenshots <name>`, and saves report/screens/NN-<name>.png at
# App Store size (6.9-inch, 1320 × 2868). It also keeps the app's log and any
# crash reports, so a crash on launch shows up in the report.
# Usage: ci-screenshots.sh <App> <DerivedData path>
set -euo pipefail

app="$1"
derived="$2"

case "$app" in
  OMM)         bundle="com.steveburlison.omm";         screens="home quicklog preset workout weights cardio stretch complete" ;;
  MutualSwipe) bundle="com.steveburlison.mutualswipe"; screens="home swipe results card import spin round roundresults startround starter starterpreview starterswipe cardphotos" ;;
  DoThisNow)   bundle="com.steveburlison.dothisnow";   screens="now pick doing tasks day dayfull inbox inboxpage replan trip tripcatchup track wake" ;;
  *) echo "Unknown app: $app"; exit 1 ;;
esac

app_path="$(find "$derived/Build/Products" -maxdepth 2 -type d -name "$app.app" -path "*iphonesimulator*" | head -1)"
if [ -z "$app_path" ]; then
  echo "No Simulator build of $app found under $derived"
  exit 1
fi

device_type="$(xcrun simctl list devicetypes -j | python3 -c '
import json, re, sys
ids = [d["identifier"] for d in json.load(sys.stdin)["devicetypes"]
       if re.search(r"iPhone-\d+-Pro-Max$", d["identifier"])]
print(max(ids, key=lambda s: int(re.search(r"iPhone-(\d+)", s).group(1))))
')"
runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"]
      if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS")]
print(max(rs, key=lambda r: [int(x) for x in r["version"].split(".")])["identifier"])
')"
echo "Using $device_type on $runtime"

udid="$(xcrun simctl create "Screens-$app" "$device_type" "$runtime")"
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$udid" "$app_path"

mkdir -p report/screens
i=1
for screen in $screens; do
  xcrun simctl launch --terminate-running-process "$udid" "$bundle" -screenshots "$screen" > /dev/null || true
  # The first launch is slower while the simulator warms up.
  if [ "$i" -eq 1 ]; then sleep 12; else sleep 6; fi
  xcrun simctl io "$udid" screenshot "report/screens/$(printf %02d "$i")-$screen.png" > /dev/null 2>&1 || true
  i=$((i + 1))
done

# Dark mode views of the first screen, for apps that support it.
if [ "$app" != "OMM" ]; then
  xcrun simctl ui "$udid" appearance dark
  first="${screens%% *}"
  xcrun simctl launch --terminate-running-process "$udid" "$bundle" -screenshots "$first" > /dev/null || true
  sleep 6
  xcrun simctl io "$udid" screenshot "report/screens/$(printf %02d "$i")-$first-dark.png" > /dev/null 2>&1 || true
  i=$((i + 1))
fi

# Do This Now runs on iPad too: photograph its two-column screens there.
if [ "$app" = "DoThisNow" ]; then
  ipad_type="$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
ids = [d["identifier"] for d in json.load(sys.stdin)["devicetypes"] if "iPad-Pro-13-inch" in d["identifier"]]
print(sorted(ids)[-1] if ids else "")
')"
  if [ -n "$ipad_type" ]; then
    echo "Using $ipad_type for iPad screens"
    ipad="$(xcrun simctl create "Screens-$app-iPad" "$ipad_type" "$runtime")"
    xcrun simctl boot "$ipad"
    xcrun simctl bootstatus "$ipad" -b > /dev/null
    xcrun simctl status_bar "$ipad" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --batteryState charged --batteryLevel 100 || true
    xcrun simctl install "$ipad" "$app_path"
    pause=20
    for screen in day replan trip; do
      xcrun simctl launch --terminate-running-process "$ipad" "$bundle" -screenshots "$screen" > /dev/null || true
      sleep "$pause"
      pause=6
      xcrun simctl io "$ipad" screenshot "report/screens/$(printf %02d "$i")-ipad-$screen.png" > /dev/null 2>&1 || true
      i=$((i + 1))
    done
    xcrun simctl shutdown "$ipad" || true
  fi
fi

xcrun simctl spawn "$udid" log show --style compact --last 10m --predicate "process == \"$app\"" \
  > report/app-log.txt 2>&1 || true
find ~/Library/Logs/DiagnosticReports -name "*$app*" -mmin -30 -exec cp {} report/ \; 2>/dev/null || true
xcrun simctl shutdown "$udid" || true

echo "Saved $(ls report/screens | wc -l | tr -d ' ') screenshots"
