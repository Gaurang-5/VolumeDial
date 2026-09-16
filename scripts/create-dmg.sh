#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-v1.1.0-beta.2}"
VERSION="${TAG#v}"
RELEASE="$ROOT/dist/releases/$TAG"
NAME="Volume-Dial-$VERSION-Apple-Silicon"
STAGING="$(mktemp -d /tmp/volumedial-dmg.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
/usr/bin/ditto -x -k "$RELEASE/$NAME.zip" "$STAGING"
test -d "$STAGING/Volume Dial.app"
/usr/bin/codesign --verify --deep --strict "$STAGING/Volume Dial.app"
ln -s /Applications "$STAGING/Applications"
/usr/bin/hdiutil create -volname 'Volume Dial' -srcfolder "$STAGING" -format UDZO "$RELEASE/$NAME.dmg"
/usr/bin/hdiutil verify "$RELEASE/$NAME.dmg"
(cd "$RELEASE" && /usr/bin/shasum -a 256 "$NAME.dmg" "$NAME.zip" "Volume-Dial-$VERSION-Source.zip" > SHA256SUMS.txt)
