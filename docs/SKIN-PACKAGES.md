# ChuckAmp skin package implementation

September 25, 2026 · MVP implementation notes

## Public workflow

`SkinPackageManager` handles external packages in process. It exposes distinct operations so UI can make side effects clear:

1. `preview(packageURL:)` validates and extracts into a private temporary directory. It does not install or change the active skin.
2. `install(packageURL:)` validates into a staging directory, then atomically moves the complete directory under the configured installed-skins root.
3. `installedSkin(id:)` resolves a previously installed skin.
4. `export(id:to:)` writes an installed skin to a new `.chuckskin` file.
5. `export(directory:to:)` validates and packages a creator directory.
6. `remove(id:)` removes only an item under the configured external-skins root. Bundled resources are outside this root.
7. `save(variation:basedOn:)` persists an accent/display variation as an independent skin.

The UI should perform file operations away from the main actor. Preview returns a `SkinPackagePreview` lease. Retain it while showing or applying preview artwork; `LiveSkinSelection.apply(_ preview:)` does this automatically. Resolve or preview before applying so any failure leaves the current skin unchanged.

## Package format and limits

`.chuckskin` is a standard ZIP archive whose root directly contains `manifest.json`. ZIPFoundation 0.9.19 performs in-process ZIP reading and writing. Its upstream repository is `weichsel/ZIPFoundation`; it is distributed under the MIT License. No subprocess or shell extractor receives untrusted input.

The default policy is:

| Limit | Value |
| --- | ---: |
| Archive file / declared compressed entries | 20 MiB |
| Total declared expanded entries | 80 MiB |
| Entries, including explicit directories | 256 |
| Width or height of one image | 4096 px |
| Aggregate decoded artwork estimate | 64 MiB |
| SVG source size | 512 KiB |

Decoded memory is conservatively estimated as width × height × 4 bytes for every manifest-referenced asset. Raster assets must be single-frame images readable by ImageIO. The restricted SVG profile requires numeric dimensions and rejects active or external content.

## Validation order

The importer checks the archive file size before opening it. It then enumerates the central directory without extracting and rejects excessive counts or declared sizes, integer overflow, absolute paths, `.` or `..`, backslashes, URL-shaped paths, non-normalized Unicode names, case-insensitive duplicate paths, and all symbolic links. CRC verification remains enabled during extraction.

Every entry is extracted separately into a newly created private directory. After extraction, the normal v1 manifest resolver validates identity, semantic keys, and asset containment. Image dimensions and aggregate decoded memory are checked last. Failed preview/import staging is deleted, and installation happens only after all checks pass.

Export follows the inverse path. It resolves the source directory, validates artwork and limits, rejects source symlinks and special files, writes a temporary deflated ZIP, checks its final size, and moves it to the requested destination. Existing destinations are not overwritten.

## Creator walkthrough

1. Copy `Skins/CreatorExample` to a writable directory.
2. Change `id`, `name`, `author`, `version`, and license text.
3. Edit the six required colors, three font roles, and artwork files. Keep `asset.window.frame`, `asset.transport.play`, and `asset.transport.pause`.
4. Call `SkinResolver.resolve(directory:)` for immediate manifest feedback.
5. Call `SkinPackageManager.export(directory:to:)` with a new `.chuckskin` destination.
6. Call `preview(packageURL:)` and inspect every player state before sharing.
7. Import the same file with `install(packageURL:)` to prove the shareable package round trip.

Skin files never define control actions, accessibility labels, focus order, layouts, high-contrast policy, or font readability overrides. Those remain app-owned for every bundled and external skin.
