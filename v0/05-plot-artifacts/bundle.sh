#!/bin/bash
# Assemble a minimal .app bundle around the SwiftPM executable so the proof gets a
# real macOS app identity (Dock, frontable window, computer-use allowlist match).
# Mirrors V0.4's bundle.sh. Ad-hoc codesigned. No resource bundles (no deps).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
swift build -c "$CONFIG"
BIN=".build/$CONFIG/CasettePlotProof"

APP="build/CasettePlotProof.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/CasettePlotProof"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CasettePlotProof</string>
  <key>CFBundleDisplayName</key><string>Casette Plot Proof</string>
  <key>CFBundleIdentifier</key><string>org.sockpuppet.casette.plotproof</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.5</string>
  <key>CFBundleExecutable</key><string>CasettePlotProof</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "APPL????" > "$APP/Contents/PkgInfo"

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
