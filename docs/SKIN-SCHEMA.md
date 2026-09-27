# MacAmp skin schema v1

September 25, 2026 · Schema version 1

MacAmp skins are declarative directories. A skin changes presentation only; it cannot define actions, layouts, scripts, network access, or audio behavior. Graphite, Paper, and creator-authored skins all pass through `SkinResolver` and produce the shared `ResolvedSkin` contract.

## Directory format

```text
MySkin/
  manifest.json
  art/
    frame.svg
    play.svg
    pause.svg
```

The creator workflow edits a directory and exports it as a `.macampskin` ZIP. Import and preview safely extract to an app-controlled directory and invoke the same resolver. The archive must contain `manifest.json` at its root, without an extra enclosing directory.

`manifest.json` uses this shape:

```json
{
  "schemaVersion": 1,
  "id": "creator.my-skin",
  "name": "My Skin",
  "author": "Creator Name",
  "version": "1.0.0",
  "license": "License or attribution text",
  "colors": {},
  "fonts": {},
  "assets": {}
}
```

`schemaVersion` must be `1`. `id` is a stable lowercase identifier made from letters, digits, dots, and hyphens. `name`, `author`, and `version` must be nonempty. `license` is optional.

Unknown semantic keys fail validation. This catches typos and ensures an older app does not silently misrender a skin made for a newer schema.

## Color roles

All color roles are required. Values are `#RRGGBB` or `#RRGGBBAA` hexadecimal strings.

| Key | Meaning |
| --- | --- |
| `color.window.background` | Main module chassis |
| `color.display.background` | Track display and playlist field |
| `color.text.primary` | Track titles and primary labels |
| `color.text.secondary` | Supporting and technical labels |
| `color.accent` | Active item, progress, and focus accent |
| `color.border` | Module and control outlines |

## Font roles

All font roles are required. v1 permits `system`, `system-rounded`, and `system-monospaced`. A skin chooses roles but does not bundle font binaries.

| Key | Meaning |
| --- | --- |
| `font.track` | Track and artist text |
| `font.technical` | Time, format, and EQ values |
| `font.controls` | Buttons and utility labels |

## Artwork roles

Asset values are relative file paths within the skin directory. Absolute paths, `.` and `..` components, Windows separators, directories, missing files, and symlinks that resolve outside the skin directory fail validation.

The frame, play, and pause roles are required in the prototype so every valid skin proves artwork customization. Remaining roles are optional and fall back to native AppKit rendering.

| Key | Required | Meaning |
| --- | --- | --- |
| `asset.window.frame` | Yes | Decorative frame over a 360 × 160 player |
| `asset.transport.play` | Yes | Play state artwork |
| `asset.transport.pause` | Yes | Pause state artwork |
| `asset.transport.previous` | No | Previous button artwork |
| `asset.transport.stop` | No | Stop button artwork |
| `asset.transport.next` | No | Next button artwork |
| `asset.slider.track` | No | General slider track |
| `asset.slider.thumb` | No | General slider thumb |
| `asset.eq.track` | No | Equalizer slider track |
| `asset.eq.thumb` | No | Equalizer slider thumb |

Bundled artwork is original, lightweight SVG. PNG and other single-frame image types recognized by ImageIO are supported. SVG is restricted to an offline profile with numeric width and height; scripts, document types, entities, links, and CSS `url()` references are rejected. The renderer should load each resolved URL through AppKit and retain native accessible controls and hit targets beneath or around decorative imagery. The app owns button actions, enabled state, focus order, labels, high-contrast behavior, readable-font overrides, and layout.

## Resolution and live application

```swift
let resolver = SkinResolver()
let graphite = try resolver.resolve(directory: graphiteDirectory)
let selection = LiveSkinSelection(activeSkin: graphite)

let observation = selection.observe { resolvedSkin in
    // Reapply semantic colors, fonts, and artwork on the main actor.
}

let paper = try resolver.resolve(directory: paperDirectory)
selection.apply(paper)
```

Resolve first and apply second. A validation failure therefore leaves the current skin unchanged. `LiveSkinSelection` is main-actor isolated and has no dependency on the queue or audio engine, so applying a skin cannot mutate playback state.

For an external preview, retain the returned `SkinPackagePreview` or pass it to `LiveSkinSelection.apply(_:)`; this retains its private extracted artwork until another skin is applied.

Accent variations change only `color.accent` and, optionally, `color.display.background`. `SkinResolver.resolve(variation:basedOn:)` creates an in-memory variation. `SkinPackageManager.save(variation:basedOn:)` saves a variation as an independently installed, exportable skin while reusing the base artwork.

Use `ResolvedSkin.color(_:)`, `font(_:)`, and `asset(_:)` with the public enums. Views must not branch on `manifest.id` or a bundled-skin name.

## Bundled skins and creator example

- `Skins/StudioGraphite` is the default charcoal and amber direction.
- `Skins/Paper` is a light warm-gray direction with teal controls.
- `Skins/Terminal` is a dark monospaced direction with green controls.
- `Skins/CreatorExample` is a copyable, editable example.

The app packager must copy bundled skin directories into the application resources and pass their resource URLs to `SkinResolver`. Swift Package resource wiring and application composition remain coordinator-owned.

See `docs/SKIN-PACKAGES.md` for archive limits, import/export APIs, and the complete creator workflow.
