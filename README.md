# ChuckAmp

ChuckAmp is a native Mac audio-player prototype inspired by classic Winamp's compact, modular feel. Product behavior is defined in [PRODUCT-DESIGN.md](PRODUCT-DESIGN.md); implementation sequencing and acceptance criteria are in [BUILD-PLAN.md](BUILD-PLAN.md).

## Requirements

- Apple-silicon Mac
- macOS 14 or newer
- Xcode 26.2 / Swift 6.2.3 (the first verified toolchain)

No personal signing identity or third-party package is required for the foundation build.

## Build and test

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/package-app.sh
open build/ChuckAmp.app
```

The package script creates a locally runnable, ad-hoc-signed app at `build/ChuckAmp.app`. It is a development artifact, not a notarized public release. `Package.swift` is the source and Xcode build graph; open it directly in Xcode to use the generated ChuckAmp scheme.

## Current state

The prototype milestone is implemented. The packaged app plays local MP3, AAC/M4A, FLAC, and WAV files through a bounded native audio pipeline; provides player, playlist, equalizer, and compact windows; restores its queue paused; and switches between the bundled Studio Graphite and Paper skins during playback. See `docs/PROTOTYPE-REPORT.md` for validation and remaining MVP work.

Shared types and service boundaries live in `Packages/ChuckAmpKit/Sources/Contracts`. Feature agents own their matching source folders. Only the coordinator changes `Package.swift`, application composition, shared contracts, dependency resolution, or packaging scripts.
