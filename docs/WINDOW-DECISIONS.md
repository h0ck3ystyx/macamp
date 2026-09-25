# ChuckAmp window feasibility decisions

September 25, 2026 · T3 spike

## Outcome

The modular window concept is feasible in AppKit at the proposed sizes. `PlayerUIWindowController` owns three native windows, keeps the player at 360 × 160 pt, supports the 360 × 40 pt compact state, and gives the playlist a 360 × 180 pt minimum. The player’s primary controls use at least 28 pt vertical hit areas at default scale.

The spike uses placeholder metadata only through `PlayerUIPreviewState`; it does not pretend to play audio or expose a fake production playback service. Transport controls route through the shared `PlayerCommand` contract when the app supplies a `PlayerUICommandRouting` implementation.

## Window behavior

- The initial layout and Reset Layout place the playlist directly below the player with the equalizer hidden. Showing the connected equalizer inserts it between player and playlist; hiding it closes that gap.
- Secondary windows snap to any player edge within 10 pt. A snapped window joins the connected set. Moving the player translates every connected secondary window by the same delta.
- Beginning a drag on a secondary window removes it from the connected set. Returning it to a player edge reconnects it.
- Closing EQ or Playlist hides that module. Closing Player hides all modules, leaving playback lifetime to the app coordinator. `show()` restores the player and visible secondary modules.
- Native titled windows retain normal focus, keyboard traversal, Mission Control, and accessibility behavior. Window tabbing is disabled because each panel has a distinct product role.
- Reset Layout is the offscreen recovery API. The app menu must expose it even when no ChuckAmp window is visible.

## Visual directions

Graphite and Paper are rendered by one view hierarchy and one semantic theme mapping. The preview deliberately avoids skin-specific control logic.

| Role | Graphite | Paper |
| --- | --- | --- |
| Chassis | charcoal graphite | warm gray paper |
| Display | recessed dark panel | pale raised sheet |
| Primary text | amber | near-black |
| Accent/current item | orange | teal |
| Secondary text | neutral light gray | neutral dark gray |

The 360 × 160 player fits elapsed time, two metadata lines, seek, four transport actions, volume, EQ/List access, and compact toggle without shrinking normal text below 10 pt. The title truncates visually and retains its full accessibility label. Compact mode keeps play/pause, title, elapsed time, and expand.

## Accessibility decisions

- Controls use native AppKit buttons, sliders, search fields, and table semantics.
- Icon-only controls have explicit accessibility labels and tooltips.
- The playing playlist row says “Playing” in its accessibility label and uses an icon plus weight and color visually.
- EQ bands expose frequency-specific labels and decibel values.
- Window labels identify Player, Equalizer, and Playlist independently.
- The app coordinator still needs native menu commands and shortcuts for play/pause, module visibility, compact mode, and Reset Layout. VoiceOver, Full Keyboard Access, Reduce Motion, multiple displays, and Spaces require hands-on validation in T5/T11.

## Requests for T6 skin rendering

The production skin resolver should provide these canonical style keys:

- `color.window.background`, `color.display.background`, `color.text.primary`, `color.text.secondary`, `color.accent`, `color.border`
- `font.track`, `font.technical`, `font.controls`
- `asset.window.frame`, `asset.transport.previous`, `asset.transport.play`, `asset.transport.pause`, `asset.transport.stop`, `asset.transport.next`
- `asset.slider.track`, `asset.slider.thumb`, `asset.eq.track`, `asset.eq.thumb`

Missing assets should fall back to native AppKit rendering. T6 can map `ResolvedSkin` values to a production theme without changing window coordination.

## Integration notes and limitations

`ChuckAmp/App` must retain one `PlayerUIWindowController`, call `show()` during launch/Dock activation, and connect menu items to `setModule`, `setCompactMode`, and `resetLayout`. Restored `WindowLayout` application is intentionally deferred because the shared contract currently stores the state but does not define display recovery policy.

This spike does not yet provide drag/drop, a bound playlist, real snapshot updates, live EQ commands, scaling, always-on-top, or screenshot automation. Those belong to T5 after T2/T4/T6 interfaces are available. AppKit window behavior still needs manual validation on multiple displays and Spaces.
