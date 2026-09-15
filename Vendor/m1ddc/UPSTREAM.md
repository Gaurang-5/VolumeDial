Source: https://github.com/waydabber/m1ddc
Revision: 04d949794102eb8df01ad3681afff6464a3eede2
License: MIT (included in LICENSE and the built app).

Local fix: use sizeof(maxValue) and sizeof(curValue), both uint16_t, instead of sizeof(2) when decoding the two-byte DDC values. This prevents a four-byte write into two-byte stack variables.

The application invokes only display listing and the volume VCP feature. Monitor reads/writes run off the UI thread and use the monitor's reported maximum.

Reply validation: reject invalid DDC/CI headers, failed VCP results, incorrect checksums, and replies for another feature before decoding a value. An invalid read leaves the app's last confirmed monitor volume intact. Regression coverage is in `tests/reply-tests.m`.

Compatibility changes: explicitly build arm64 with a macOS 14 deployment target and the selected Xcode SDK; allow 50 ms for slower DDC devices; enumerate up to 32 online displays instead of four; initialize each display record and check enumeration errors. This project does not add an Intel transport or guarantee support where DDC is blocked by the hardware path.
