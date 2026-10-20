#!/bin/bash
# Run on the Mac. Gets the latest code, signs one app with the Apple ID you've
# added in Xcode (Settings → Accounts), and uploads it to App Store Connect.
# About 10–30 minutes later the build appears under TestFlight.
#
#   ./scripts/ship.sh OMM
#   ./scripts/ship.sh DoThisNow
#   ./scripts/ship.sh MutualSwipe
#
# The Team ID comes from the project settings. To use another one, run with
# TEAM_ID=XXXXXXXXXX, or put it in scripts/team-id.
set -euo pipefail

app="${1:-}"
case "$app" in
  OMM|DoThisNow|MutualSwipe) ;;
  *) echo "Usage: ./scripts/ship.sh OMM | DoThisNow | MutualSwipe"; exit 1 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode isn't the active developer tool. Run: sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi

echo "→ Getting the latest code"
git pull --ff-only

team="${TEAM_ID:-}"
if [ -z "$team" ] && [ -f scripts/team-id ]; then
  team="$(tr -d '[:space:]' < scripts/team-id)"
fi
team_setting=()
if [ -n "$team" ]; then
  team_setting=("DEVELOPMENT_TEAM=$team")
fi

# Every upload needs a new build number. The date and time always go up.
build_number="$(date +%Y%m%d%H%M)"
out="$root/build/$app"
rm -rf "$out"
mkdir -p "$out"

echo "→ Archiving $app (build $build_number)"
xcodebuild \
  -project "$app/$app.xcodeproj" \
  -scheme "$app" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$out/$app.xcarchive" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$build_number" \
  "${team_setting[@]+"${team_setting[@]}"}" \
  archive > "$out/archive.log" 2>&1 || {
    tail -40 "$out/archive.log"
    echo "✗ Archive failed. Full log: $out/archive.log"
    exit 1
  }

cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST

echo "→ Signing and uploading to App Store Connect"
xcodebuild \
  -exportArchive \
  -archivePath "$out/$app.xcarchive" \
  -exportOptionsPlist "$out/ExportOptions.plist" \
  -exportPath "$out/export" \
  -allowProvisioningUpdates > "$out/upload.log" 2>&1 || {
    tail -40 "$out/upload.log"
    echo "✗ Upload failed. Full log: $out/upload.log"
    exit 1
  }

echo
echo "✓ Uploaded $app build $build_number."
echo "  It shows up in App Store Connect → TestFlight in about 10–30 minutes."
