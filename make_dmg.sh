#!/bin/zsh
# Syncwright. Copyright © 2026 Ray Munro. All rights reserved.
# Builds the app and packages it with its documentation as dist/Syncwright-<version>.dmg
set -e
cd "$(dirname "$0")"
VER=$(grep -o 'CFBundleShortVersionString</key><string>[^<]*' build_app.sh | sed 's/.*<string>//')
NAME="Syncwright"
VOL="$NAME $VER"
OUT="dist/Syncwright-$VER.dmg"
./build_app.sh
python3 tools/make_docs_pdf.py
mkdir -p dist; rm -f "$OUT" dist/rw.dmg
STAGE=$(mktemp -d)
cp -R "$NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp docs/Syncwright-Documentation.pdf "$STAGE/Documentation.pdf"
# Every chapter as readable files too, keeping the folder layout so the links between them still work
mkdir -p "$STAGE/Guides/docs/assets" "$STAGE/Guides/Resources"
cp README.md CHANGELOG.md "$STAGE/Guides/"
cp docs/*.md "$STAGE/Guides/docs/"
cp docs/assets/* "$STAGE/Guides/docs/assets/"
cp Resources/AppIcon-1024.png "$STAGE/Guides/Resources/"
cp LICENSE "$STAGE/LICENSE.txt"
mkdir "$STAGE/.background"; swift tools/make_dmg_bg.swift "$STAGE/.background/bg.png"
# Custom icon for the disk image file and the mounted disk
swift tools/make_dmg_icon.swift Resources/AppIcon-1024.png Resources/DiskImageIcon-1024.png >/dev/null
ICONSET=$(mktemp -d)/DiskImage.iconset; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/DiskImageIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/DiskImageIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
VOLICON="${ICONSET:h}/VolumeIcon.icns"
iconutil -c icns "$ICONSET" -o "$VOLICON"
hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -ov dist/rw.dmg >/dev/null
ATTACH=$(hdiutil attach dist/rw.dmg -readwrite -noverify -noautoopen)
DEV=$(echo "$ATTACH" | awk '/Apple_HFS/ {print $1; exit}')
MNT=$(echo "$ATTACH" | awk -F'\t' '/Apple_HFS/ {print $NF; exit}')
[ "$MNT" = "/Volumes/$VOL" ] || { echo "error: image mounted at $MNT; eject other \"$VOL\" disks and try again"; hdiutil detach "$DEV" -quiet; exit 1; }
sleep 2
# Lay out the window (best effort: needs Finder automation permission the first time)
osascript <<OSA || echo "note: couldn't style the window; the DMG still works"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 640}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set background picture of opts to file ".background:bg.png"
    set position of item "$NAME.app" of container window to {180, 170}
    set position of item "Applications" of container window to {480, 170}
    set position of item "Documentation.pdf" of container window to {170, 360}
    set position of item "Guides" of container window to {330, 360}
    set position of item "LICENSE.txt" of container window to {490, 360}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
chflags hidden "/Volumes/$VOL/.background" 2>/dev/null || true
# The disk icon goes on last: hdiutil leaves .VolumeIcon.icns out of a folder build, and Finder's layout step removes it
cp "$VOLICON" "/Volumes/$VOL/.VolumeIcon.icns"
SetFile -c icnC "/Volumes/$VOL/.VolumeIcon.icns"
SetFile -a V "/Volumes/$VOL/.VolumeIcon.icns"  # keep the icon file itself hidden
SetFile -a C "/Volumes/$VOL"                   # and use it as the disk's icon
GetFileInfo -a "/Volumes/$VOL" | grep -q C || { echo "error: couldn't set the disk icon"; exit 1; }
sync
hdiutil detach "$DEV" -quiet
hdiutil convert dist/rw.dmg -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f dist/rw.dmg; rm -rf "$STAGE"
ID=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | awk '{print $2}')
[ -n "$ID" ] && codesign --force --sign "$ID" "$OUT"
# Give the .dmg file itself the icon in Finder (stored as Finder metadata, so it shows on this Mac)
swift tools/set_file_icon.swift Resources/DiskImageIcon-1024.png "$OUT"
echo "Built: $PWD/$OUT ($(du -h "$OUT" | cut -f1))"
