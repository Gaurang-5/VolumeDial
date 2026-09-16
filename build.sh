#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
xcrun swift build -c release --triple arm64-apple-macosx14.0 --sdk "$SDK_PATH"
SWIFT_BIN_DIR=$(xcrun swift build -c release --triple arm64-apple-macosx14.0 --sdk "$SDK_PATH" --show-bin-path)
STAGING_DIR=$(mktemp -d /tmp/volumedial-build.XXXXXX)
APP="$STAGING_DIR/Volume Dial.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Recompile the helper with the same architecture, SDK, and minimum OS as the app.
make -B -C Vendor/m1ddc SDKROOT="$SDK_PATH"
mkdir -p "$APP/Contents/Helpers"
cp Vendor/m1ddc/m1ddc "$APP/Contents/Helpers/m1ddc"
cp Vendor/m1ddc/LICENSE "$APP/Contents/Resources/m1ddc-LICENSE.txt"
cp Resources/VolumeDial.icns "$APP/Contents/Resources/VolumeDial.icns"
cp LICENSE "$APP/Contents/Resources/Volume-Dial-LICENSE.txt"
codesign --force --sign - "$APP/Contents/Helpers/m1ddc"
cp "$SWIFT_BIN_DIR/VolumeDial" "$APP/Contents/MacOS/VolumeDial"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VolumeDial</string>
<key>CFBundleIdentifier</key><string>com.gaurang.volumedial</string>
<key>CFBundleName</key><string>Volume Dial</string>
<key>CFBundleDisplayName</key><string>Volume Dial</string>
<key>CFBundleIconFile</key><string>VolumeDial</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Finder can attach layout metadata after the first launch; codesign rejects it.
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
bash scripts/verify-build.sh "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p dist
ditto --norsrc "$APP" 'dist/Volume Dial.app'
# Package the clean staged bundle before cloud-backed Documents adds Finder metadata.
ditto -c -k --sequesterRsrc --keepParent "$APP" 'dist/Volume-Dial-Apple-Silicon.zip'
printf 'Built: %s/dist/Volume Dial.app\n' "$PWD"
