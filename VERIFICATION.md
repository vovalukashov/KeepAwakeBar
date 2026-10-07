# Verification — October 7, 2026

- Xcode Release archive succeeded; macOS 13+, universal arm64 and x86_64.
- App and embedded helper signed with Developer ID Application: Vladimir Lukashov (5KGN4ZW626), secure timestamp, and Hardened Runtime.
- Deep/strict code signature verification passed.
- Uploaded to Apple using Xcode; notarization ticket successfully stapled and validated.
- Gatekeeper assessment: accepted, source=Notarized Developer ID.
- Ready-to-distribute ZIP extraction and the app mounted from the DMG passed signature, ticket, and Gatekeeper checks. DMG checksum verification passed.
- The previous functional build passed all eight Core tests. This release changes archive packaging and signing, not application behavior.
- Clean second-Mac installation, Intel hardware, interactive privileged toggles, and physical lid-close behavior have not been verified.

The original October 5 release was ad-hoc signed. Use the signed release for distribution.
