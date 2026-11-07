#!/bin/zsh
# Syncwright. Copyright © 2026 Ray Munro. All rights reserved.
set -e
cd "$(dirname "$0")"
swift build -c release
BIN=$(swift build -c release --show-bin-path)/Syncwright
APP="Syncwright.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Syncwright"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Syncwright</string>
<key>CFBundleDisplayName</key><string>Syncwright</string>
<key>CFBundleIdentifier</key><string>com.raymondmunro.syncwright</string>
<key>CFBundleExecutable</key><string>Syncwright</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Ray Munro. All rights reserved.</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.video</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSDesktopFolderUsageDescription</key><string>Syncwright reads and writes the video files you choose.</string>
<key>NSDocumentsFolderUsageDescription</key><string>Syncwright reads and writes the video files you choose.</string>
<key>NSRemovableVolumesUsageDescription</key><string>Syncwright reads and writes the video files you choose.</string>
</dict></plist>
PL
ID=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | awk '{print $2}')
codesign --force --sign "${ID:--}" "$APP"
echo "Signed with: ${ID:-ad-hoc}"
echo "Built: $PWD/$APP"
