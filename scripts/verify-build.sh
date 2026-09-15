#!/bin/bash
set -euo pipefail
APP=${1:-dist/Volume Dial.app}
for executable in "$APP/Contents/MacOS/VolumeDial" "$APP/Contents/Helpers/m1ddc"; do
    architectures=$(xcrun lipo -archs "$executable")
    minimum=$(xcrun vtool -show-build "$executable" | awk '$1 == "minos" { print $2 }')
    if [[ "$architectures" != arm64 || "$minimum" != 14.0 ]]; then
        printf 'FAIL: %s: architecture=%s, minimum macOS=%s (expected arm64 / 14.0)\n' "$executable" "$architectures" "$minimum" >&2
        exit 1
    fi
    printf 'PASS: %s: Apple Silicon, macOS %s+\n' "$(basename "$executable")" "$minimum"
done
