#!/usr/bin/env python3
"""Stage the existing tested app for a GitHub draft without rebuilding or uploading."""
import hashlib
import json
import plistlib
import shutil
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TAG = "v1.1.0-beta.1"
ASSET = "Volume-Dial-1.1.0-beta.1-Apple-Silicon.zip"
SOURCE_ASSET = "Volume-Dial-1.1.0-beta.1-Source.zip"


def inspect_binary(data):
    if len(data) < 32:
        raise ValueError("Truncated Mach-O header")
    magic, cpu, _, _, count, command_bytes, _, _ = struct.unpack_from("<8I", data)
    if magic != 0xFEEDFACF or cpu != 0x0100000C:
        raise ValueError("Expected an Apple Silicon-only Mach-O executable")
    offset, end = 32, 32 + command_bytes
    if end > len(data):
        raise ValueError("Truncated Mach-O load commands")
    for _ in range(count):
        if offset + 8 > end:
            raise ValueError("Invalid Mach-O load command")
        command, size = struct.unpack_from("<2I", data, offset)
        if size < 8 or offset + size > end:
            raise ValueError("Invalid Mach-O command size")
        if command == 0x32 and size >= 24:
            platform, minimum = struct.unpack_from("<2I", data, offset + 8)
            if platform != 1 or minimum != 0x000E0000:
                raise ValueError("Expected a macOS 14.0 minimum deployment target")
            return {"architecture": "arm64", "minimum_macos": "14.0"}
        offset += size
    raise ValueError("Missing Mach-O deployment target")


def unsigned_payload(data):
    """Exclude only the embedded signature, whose resource hash changes on signing."""
    offset = 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, size = struct.unpack_from("<2I", data, offset)
        if command == 0x1D and size == 16:
            start, length = struct.unpack_from("<2I", data, offset + 8)
            if start < offset + size or start + length > len(data):
                raise ValueError("Invalid embedded signature range")
            return data[:start] + data[start + length:]
        offset += size
    raise ValueError("Missing embedded signature")


def main():
    source = ROOT / "dist/Volume-Dial-Apple-Silicon.zip"
    with zipfile.ZipFile(source) as archive:
        if archive.testzip() is not None:
            raise ValueError("The app ZIP failed its integrity check")
        prefix = "Volume Dial.app/Contents/"
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        if info["CFBundleShortVersionString"] != "1.1.0" or info["LSMinimumSystemVersion"] != "14.0":
            raise ValueError("Bundle version or minimum OS does not match this release")
        binaries = {name: inspect_binary(archive.read(prefix + name))
                    for name in ("MacOS/VolumeDial", "Helpers/m1ddc")}
        archive.read(prefix + "Resources/m1ddc-LICENSE.txt")
    destination = ROOT / "dist/releases" / TAG
    destination.mkdir(parents=True, exist_ok=True)
    asset = destination / ASSET
    with tempfile.TemporaryDirectory(prefix="volumedial-release-") as temporary:
        subprocess.run(["/usr/bin/ditto", "-x", "-k", str(source), temporary], check=True)
        app = Path(temporary) / "Volume Dial.app"
        shutil.copyfile(ROOT / "LICENSE", app / "Contents/Resources/Volume-Dial-LICENSE.txt")
        subprocess.run(["/usr/bin/xattr", "-d", "com.apple.FinderInfo", str(app)], capture_output=True)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)], check=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(asset)], check=True)
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(asset) as prepared:
        for name in binaries:
            if unsigned_payload(original.read(prefix + name)) != unsigned_payload(prepared.read(prefix + name)):
                raise ValueError("Release preparation changed a tested executable outside its signature")
        if prepared.read(prefix + "Resources/Volume-Dial-LICENSE.txt") != (ROOT / "LICENSE").read_bytes():
            raise ValueError("Project license missing from app")
        if prepared.testzip() is not None:
            raise ValueError("Prepared ZIP failed its integrity check")
    files = [ROOT / name for name in ("Package.swift", "README.md", "LICENSE", "THIRD_PARTY_NOTICES.md", ".gitignore", "build.sh", "docs/RELEASING.md", f"docs/releases/{TAG}.md")]
    for folder in ("Sources", "Tests", "scripts", ".github", "Vendor/m1ddc"):
        files.extend(path for path in (ROOT / folder).rglob("*") if path.is_file()
                     and not any(part in (".git", ".objects", "__pycache__", "library") for part in path.parts)
                     and path.name not in ("m1ddc", ".DS_Store"))
    source_asset = destination / SOURCE_ASSET
    with zipfile.ZipFile(source_asset, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(set(files)):
            archive.write(path, str(Path("VolumeDial") / path.relative_to(ROOT)))
    checksums = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in (asset, source_asset)}
    (destination / "SHA256SUMS.txt").write_text("".join(f"{digest}  {name}\n" for name, digest in checksums.items()))
    shutil.copyfile(ROOT / "docs/releases" / f"{TAG}.md", destination / "RELEASE_NOTES.md")
    manifest = {"tag": TAG, "title": "Volume Dial 1.1.0 — Apple Silicon beta",
                "draft": True, "prerelease": True, "asset": ASSET,
                "source_asset": SOURCE_ASSET, "sha256": checksums, "binaries": binaries,
                "signing": "ad-hoc", "notarized": False}
    (destination / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared {destination}")
    print("ZIP integrity, unchanged executables, staged signatures, arm64 architecture, macOS 14 targets, version, and both licenses verified.")
    print("No files have been uploaded or published.")


if __name__ == "__main__":
    main()
