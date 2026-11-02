#!/bin/zsh
# Builds NonNet, installs + opens it on the connected iPhone, then opens it on this Mac.
set -e
cd "$(dirname "$0")"

IPHONE=$(xcrun devicectl list devices 2>/dev/null | awk '/connected/ && /physical/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i}' | head -1)

if [[ -n "$IPHONE" ]]; then
  echo "▶ iPhone $IPHONE"
  xcodebuild -project Blip.xcodeproj -scheme Blip -destination "id=$IPHONE" -allowProvisioningUpdates -derivedDataPath build build -quiet
  xcrun devicectl device install app --device "$IPHONE" build/Build/Products/Debug-iphoneos/Blip.app >/dev/null
  if xcrun devicectl device process launch --terminate-existing --device "$IPHONE" io.cdav.blip >/dev/null 2>&1; then
    echo "  opened on iPhone"
  else
    echo "  installed on iPhone (unlock it and open Blip)"
  fi
else
  echo "▶ no iPhone connected, skipping"
fi

echo "▶ Mac"
xcodebuild -project Blip.xcodeproj -scheme Blip -destination 'platform=macOS,variant=Designed for iPad' -allowProvisioningUpdates -derivedDataPath build-mac build -quiet
# An iPhone/iPad app runs on Apple silicon Macs inside a wrapper bundle.
rm -rf build-mac/Mac && mkdir -p build-mac/Mac/NonNet.app/Wrapper
cp -R build-mac/Build/Products/Debug-iphoneos/Blip.app build-mac/Mac/NonNet.app/Wrapper/
ln -s Wrapper/Blip.app build-mac/Mac/NonNet.app/WrappedBundle
pkill -f "Wrapper/Blip.app/Blip" 2>/dev/null && sleep 1 || true
# Keep the Mac app in /Applications so it shows up in Launchpad, Spotlight and the Dock.
rm -rf /Applications/NonNet.app && cp -R build-mac/Mac/NonNet.app /Applications/NonNet.app
open /Applications/NonNet.app
echo "  opened on Mac"
