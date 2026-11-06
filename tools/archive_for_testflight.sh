#!/usr/bin/env bash
# One command from a Mac that is signed in to Xcode with your Apple ID:
#   tools/archive_for_testflight.sh YOURTEAMID          # live EPGTalk feed (default, owner testing)
#   tools/archive_for_testflight.sh YOURTEAMID sample   # sample data only
# Builds, signs (automatic), and uploads to App Store Connect / TestFlight. No secrets, no API key.
set -euo pipefail
TEAM="${1:?Usage: $0 YOURTEAMID [sample]}"
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
BUILD="$(date +%Y%m%d%H%M)"      # every upload needs a new build number
LIVE=""; if [ "${2:-}" = "sample" ]; then LIVE="TVG_LIVE_FEED_ENABLED=NO"; echo "Sample data only for this build."; fi
OUT="build/testflight"; rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild archive -project TouchTVGuide.xcodeproj -scheme TouchTVGuide -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$OUT/TouchTVGuide.xcarchive" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic CURRENT_PROJECT_VERSION="$BUILD" $LIVE
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${TEAM}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$OUT/TouchTVGuide.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates
echo "Uploaded build $BUILD. It shows in TestFlight after App Store Connect finishes processing (about 5-15 minutes)."
