#!/bin/bash
# Assemble a minimal .app bundle around the SwiftPM executable so the proof gets a
# real macOS app identity (Dock, frontable window, computer-use allowlist match).
# Mirrors the main app's build.sh approach. Ad-hoc codesigned.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
swift build -c "$CONFIG"
BIN=".build/$CONFIG/CasetteLatexProof"

APP="build/CasetteLatexProof.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/CasetteLatexProof"

# Copy any bundled resource bundles SwiftPM produced (MathJaxSwift ships JS bundles).
for b in .build/"$CONFIG"/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CasetteLatexProof</string>
  <key>CFBundleDisplayName</key><string>Casette Math Proof</string>
  <key>CFBundleIdentifier</key><string>org.sockpuppet.casette.latexproof</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.4</string>
  <key>CFBundleExecutable</key><string>CasetteLatexProof</string>
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
