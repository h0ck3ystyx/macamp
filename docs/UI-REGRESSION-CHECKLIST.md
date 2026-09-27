# ChuckAmp UI regression checklist

Run this checklist against the packaged `build/ChuckAmp.app` with at least two playable local tracks. Preserve the user's session before testing and restore it afterward.

## Skin and scale matrix

For Studio Graphite, Paper, and Terminal at 100%, 125%, and 150%:

- Player, equalizer, and playlist edges remain flush when attached.
- Transport, utility, playlist, bypass, and reset controls are visible and clickable.
- Text and control hit targets enlarge with the selected interface scale.
- Long now-playing metadata truncates instead of changing the player width.
- Selecting a playlist row does not resize any module.

Expected default frame sizes include the 32-point macOS title bar:

| Scale | Player | Equalizer | Playlist |
| --- | --- | --- | --- |
| 100% | 360 × 192 | 360 × 232 | 360 × 292 |
| 125% | 450 × 232 | 450 × 282 | 450 × 357 |
| 150% | 540 × 272 | 540 × 332 | 540 × 422 |

## Window behavior

- Enlarge the playlist, select another row, search for one result, and clear the search. Its frame must not change.
- Toggle compact mode and expand it again. Attached modules move with the player and retain their own sizes.
- Close the equalizer with its title-bar button. The playlist moves up to the player; showing the equalizer restores the three-window stack.
- Move a secondary module away, then move the player. The detached module stays put.
- Move the secondary module within the snap threshold. It joins the group and follows subsequent player movement.
- Choose Reset Layout. Player and playlist return on screen at 100%; equalizer is recoverable from the Window menu.

## Relaunch and state

- Quit and relaunch after resizing the playlist. Its exact frame, active skin, scale, compact state, and module visibility return.
- Play a track restored from the previous session. It starts without an authorization error when its stored bookmark or readable local path remains valid.
- Clear Playlist, confirm playback stops and the empty state appears, then use Undo to restore the queue.

Record the date, macOS version, display arrangement, skin/scale combinations, deviations, and screenshots in `docs/TEST-REPORT.md`.
