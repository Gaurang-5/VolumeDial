# Device compatibility

Built-in speakers, headphones, and devices exposing writable Core Audio volume controls can be adjusted. Multi-output and aggregate devices are traversed to their active members. Every controllable output receives the same requested percentage. Zero and 100% set all controllable channels to their respective endpoints.

Outputs without writable controls are listed in the right-click menu as **Hardware volume only**. Their volume is not changed. In partially controllable groups, the dial and mute action apply only to controllable channels.

Hardware verification covers the available Apple Silicon Mac with **BenQ EW2790U** and **MacBook Pro Speakers**, both individually and in a multi-output group. The BenQ is controlled through DDC; its reported maximum is 50, so a dial position of 20% writes 10/50. Other monitors are probed for volume support and scaled using their own maximum, without a brand-specific allowlist. DDC writes are coalesced off the UI thread and verified after the monitor settles. No audio driver is installed.

External-monitor compatibility depends on DDC/CI volume support and the complete connection path. A display must expose writable volume through Core Audio or support the DDC volume feature; a dock, adapter, DisplayLink connection, or some Mac ports may prevent DDC communication. Enable DDC/CI in the monitor's own settings if provided, and try a direct USB-C/DisplayPort connection if a dock blocks control. TVs, displays without speakers/audio output, and proprietary control protocols are not universally supported. The app does not route audio through a virtual driver as a fallback.

Audio and display names are matched without differences in capitalization, spacing, or punctuation. Duplicate model names and generic names such as “HDMI” are left unmatched when the physical monitor cannot be identified unambiguously, rather than risking a command to the wrong screen. Hardware with ambiguous names requires additional mapping support before DDC control can be offered.

The macOS 14 minimum is verified in the binaries; runtime testing on every M-series model, older supported macOS release, monitor, and adapter has not been performed. Treat other combinations as unverified until tested on those devices.

