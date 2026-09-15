# Volume Dial

Native macOS menu bar volume dial inspired by a sculpted physical knob, with silver and dark finishes. Built for **Apple Silicon (M-series) Macs running macOS 14 or later**. Intel Macs are not supported. Uses SwiftUI, AppKit, Core Audio, and a bundled MIT-licensed m1ddc helper.

## Run

For a packaged release, download the **Apple-Silicon.zip** asset from this repository's Releases page, extract it, and move **Volume Dial.app** to **Applications**. GitHub's automatically generated source-code ZIP is not the installable app. See the release notes for the signing/notarization status of each download.

Build with `bash build.sh`, then open `dist/Volume Dial.app`. The app stays in the menu bar without a Dock icon. Enable **Launch at login** in the right-click menu after placing the bundle in a stable location.

The build also creates `dist/Volume-Dial-Apple-Silicon.zip`. Both executables are checked for arm64 architecture and a macOS 14 deployment target. This is a local beta build: Developer ID signing and notarization are still required for a normal public-download installation experience.

## Controls

- Click the menu bar dial to open or close the panel.
- Scroll over the menu bar icon or the large dial to adjust volume.
- Click or drag to a position on the dial to set that percentage directly.
- Click the dial, then use arrow keys for 1% steps; Shift + arrows for 10% steps.
- Right-click the panel for mute and restore.
- Click the sun/moon button in the top-right corner to toggle Light and Dark.
- Right-click → **Appearance** → **System**, **Light**, or **Dark**. The default follows macOS; your choice is remembered.
- Click the current output name beneath the dial to choose another output.
- Right-click the panel for trackpad haptics, launch at login, device limitations, and Quit.
- Click outside or press Escape to dismiss the panel.

The active output and volume refresh twice per second. Haptics require supported trackpad hardware and macOS settings. The panel stays within the display containing its menu bar item, including displays with negative coordinates.

## Device support

Built-in speakers, headphones, and devices exposing writable Core Audio volume controls can be adjusted. Multi-output and aggregate devices are traversed to their active members. Every controllable output receives the same requested percentage. Zero and 100% set all controllable channels to their respective endpoints.

Outputs without writable controls are listed in the right-click menu as **Hardware volume only**. Their volume is not changed. In partially controllable groups, the dial and mute action apply only to controllable channels.

Hardware verification covers the available Apple Silicon Mac with **BenQ EW2790U** and **MacBook Pro Speakers**, both individually and in a multi-output group. The BenQ is controlled through DDC; its reported maximum is 50, so a dial position of 20% writes 10/50. Other monitors are probed for volume support and scaled using their own maximum, without a brand-specific allowlist. DDC writes are coalesced off the UI thread and verified after the monitor settles. No audio driver is installed.

External-monitor compatibility depends on DDC/CI volume support and the complete connection path. A display must expose writable volume through Core Audio or support the DDC volume feature; a dock, adapter, DisplayLink connection, or some Mac ports may prevent DDC communication. Enable DDC/CI in the monitor's own settings if provided, and try a direct USB-C/DisplayPort connection if a dock blocks control. TVs, displays without speakers/audio output, and proprietary control protocols are not universally supported. The app does not route audio through a virtual driver as a fallback.

Audio and display names are matched without differences in capitalization, spacing, or punctuation. Duplicate model names and generic names such as “HDMI” are left unmatched when the physical monitor cannot be identified unambiguously, rather than risking a command to the wrong screen. Hardware with ambiguous names requires additional mapping support before DDC control can be offered.

The macOS 14 minimum is verified in the binaries; runtime testing on every M-series model, older supported macOS release, monitor, and adapter has not been performed. Treat other combinations as unverified until tested on those devices.

## Verification

Run `swift test` for volume limits, angle wrap, exact group percentages, monitor scaling, virtual-device filtering, mute restore after membership changes, external hardware mute, and panel placement on primary and secondary displays.

Run `make -C Vendor/m1ddc test` for DDC reply validation. Empty, damaged, unsupported, or mismatched replies are discarded so background polling keeps the last confirmed monitor level. In a multi-output group, a failed monitor read must not be averaged as zero.

The outside-click handler excludes the menu bar button; clicking the icon again closes the panel without reopening it on mouse-up. Optional `--trace-volume` diagnostics write volume requests, hardware observations, and panel toggles to stderr without recording audio.

Run `"dist/Volume Dial.app/Contents/MacOS/VolumeDial" --diagnose` for a read-only view of the current route and available controls, including the bundled monitor helper. Run `bash scripts/verify-build.sh` to verify the architecture and minimum OS of both executables. The local bundle is ad-hoc signed, not notarized for distribution.

Virtual utility devices (such as ZoomAudioDevice and Hue Sync Audio) and hidden driver devices are excluded from the picker. Physical outputs and public aggregate/multi-output groups remain. FineTune was consulted as a reference for hardware/DDC volume separation and standard Core Audio routing; no FineTune source is included.

## License and release preparation

Volume Dial is MIT-licensed. See [LICENSE](LICENSE) and [third-party notices](THIRD_PARTY_NOTICES.md).

Run `python3 scripts/prepare-release.py` to stage the existing tested app, release notes, source archive, and SHA-256 checksums. This does not rebuild, upload, or publish the app. See [the release guide](docs/RELEASING.md) for the remaining publication steps.
