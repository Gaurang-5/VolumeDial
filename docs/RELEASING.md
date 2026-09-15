# Releasing Volume Dial

## Prepared release

- Proposed repository: `Gaurang-5/VolumeDial` (public, MIT license).
- Tag: `v1.1.0-beta.1`.
- Title: `Volume Dial 1.1.0 — Apple Silicon beta`.
- Mark as **pre-release**; keep it as a **draft** until the files and notes have been reviewed.
- Assets are staged under `dist/releases/v1.1.0-beta.1/`.

`python3 scripts/prepare-release.py` verifies the existing app ZIP, checks both Mach-O binaries for arm64 and macOS 14, includes the project license, re-signs the staged bundle ad hoc, and creates app/source ZIPs with checksums. It does not modify the running app or publish anything. Source packaging excludes `.git`, compiler output, local app bundles, and internal planning documents.

The packager checks that both tested executables remain byte-for-byte unchanged outside their embedded code signatures. Adding the license changes the app's signed resource hash, so that signing data is expected to change.

## Before publication

Review `RELEASE_NOTES.md`, the two ZIPs, and `SHA256SUMS.txt` in the staged release directory. The public repository should contain the files in the prepared source archive, not the `dist` directory. Release assets belong on the GitHub release.

The current build is ad-hoc signed and **not notarized**. For this beta, the release notes disclose that macOS may block first launch and link to Apple's installation guidance. Do not describe this build as Apple-verified or as tested on every M-series Mac or external monitor.

The current machine reports that the Xcode/Apple SDK license must be accepted before its developer tools can run. The owner needs to open Xcode and review/accept the agreement before rebuilding. No agreement was accepted by the release-preparation script. No Developer ID signing identity was available during preparation.

For a general release, configure a Developer ID Application identity, sign the helper and app with the hardened runtime, submit the package using `notarytool`, staple Apple's ticket, and test installation on a separate Mac. The current build script deliberately uses ad-hoc signing and must be updated before that release path is used. Consult [Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## GitHub draft

After the repository's source commit and `v1.1.0-beta.1` tag exist, create a draft with the prepared notes and assets. GitHub's [release documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository) covers reviewing and publishing the draft.

```sh
gh release create v1.1.0-beta.1 \
  --repo Gaurang-5/VolumeDial \
  --verify-tag --draft --prerelease \
  --title 'Volume Dial 1.1.0 — Apple Silicon beta' \
  --notes-file dist/releases/v1.1.0-beta.1/RELEASE_NOTES.md \
  dist/releases/v1.1.0-beta.1/Volume-Dial-1.1.0-beta.1-Apple-Silicon.zip \
  dist/releases/v1.1.0-beta.1/Volume-Dial-1.1.0-beta.1-Source.zip \
  dist/releases/v1.1.0-beta.1/SHA256SUMS.txt
```

Review the uploaded files and notes, then publish the pre-release when approved. Keep account credentials, signing certificates, and private keys out of the repository and release assets.
