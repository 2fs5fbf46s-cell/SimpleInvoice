#!/usr/bin/env bash
# Re-render the app icon and launch logo after changing SBWLogoMark.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
ASSETS="SmallBiz Workspace/Assets.xcassets"
TMP="$(mktemp -d)"
swiftc -parse-as-library -o "$TMP/render" scripts/render-brand-assets.swift "SmallBiz Workspace/SBWLogoMark.swift" 2>&1 | grep -v warning || true
mkdir -p "$ASSETS/LaunchLogo.imageset"
"$TMP/render" "$ASSETS/AppIcon.appiconset" "$ASSETS/LaunchLogo.imageset"
# The App Store refuses an icon with an alpha channel.
python3 -c "from PIL import Image; p='$ASSETS/AppIcon.appiconset/AppIcon-1024.png'; Image.open(p).convert('RGB').save(p)"
rm -rf "$TMP"
