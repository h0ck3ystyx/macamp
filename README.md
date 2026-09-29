# MacAmp

MacAmp is a native Mac audio-player prototype inspired by classic Winamp's compact, modular feel. Product behavior is defined in [PRODUCT-DESIGN.md](PRODUCT-DESIGN.md); implementation sequencing and acceptance criteria are in [BUILD-PLAN.md](BUILD-PLAN.md). The path from the current MVP candidate to TestFlight and App Review is defined in [docs/APP-STORE-RELEASE-PLAN.md](docs/APP-STORE-RELEASE-PLAN.md).

## Requirements

- Apple-silicon Mac
- macOS 14 or newer
- Xcode 26.2 / Swift 6.2.3 (the first verified toolchain)

SwiftPM resolves the pinned ZIPFoundation 0.9.19 dependency used for safe `.macampskin` archives. No personal signing identity is required for a local build.

## Build and test

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/package-app.sh
./scripts/validate-app-bundle.sh
open build/MacAmp.app
```

The package script creates a locally runnable, ad-hoc-signed app at `build/MacAmp.app`. It is a development artifact, not an App Store-signed or notarized public release. `Package.swift` is the current source and Xcode build graph; open it directly in Xcode to use the generated MacAmp scheme.

The native `MacAmp-AppStore` scheme in `MacAmp.xcodeproj` is the archive and managed-signing path. This command creates and validates an unsigned archive without requiring personal credentials:

```sh
./scripts/archive-app-store.sh
```

For an authorized signing environment, set `MACAMP_ALLOW_SIGNING=1`, `MACAMP_DEVELOPMENT_TEAM`, and the final `MACAMP_BUNDLE_IDENTIFIER`. Optional `MACAMP_VERSION` and `MACAMP_BUILD_NUMBER` values override the archive version. Xcode must have access to the matching App ID, distribution certificate, and provisioning profile. Once the signed archive passes validation, `./scripts/export-app-store.sh` produces the App Store Connect delivery package without uploading it.

## Current state

The MVP candidate plays the full tested local format matrix through a bounded native audio pipeline; provides player, playlist, equalizer, and compact windows; imports and exports playlists; keeps named playlists; restores playback and presentation state paused; handles system media commands; and includes Studio Graphite, Paper, Terminal, accent variants, and validated `.macampskin` packages. See `docs/TEST-REPORT.md` for current evidence and checks that still need physical or external access.

Shared types and service boundaries live in `Packages/MacAmpKit/Sources/Contracts`. Feature agents own their matching source folders. Only the coordinator changes `Package.swift`, application composition, shared contracts, dependency resolution, or packaging scripts.
