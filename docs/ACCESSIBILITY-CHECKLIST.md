# MacAmp accessibility checklist

Date: September 27, 2026

## Automated coverage

- Every icon-only player, compact-player, playlist, and equalizer action has an accessibility label and tooltip.
- Play/Pause labels follow the current playback state.
- Seek, volume, preamp, and band sliders expose human-readable time, percent, and decibel values.
- Player, compact-player, playlist, and equalizer modules define explicit keyboard focus loops.
- Remove, Clear, Move Up, Move Down, transport, and Stop disable when their action has no valid target.
- Space invokes Play/Pause through the native Playback menu. Stop, Previous Track, and Next Track also have native menu commands.
- Playing, selected, and unavailable playlist rows include a non-color marker and state in their accessibility label.
- Studio Graphite, Paper, and Terminal primary text, secondary text, and accent colors maintain at least 4.5:1 contrast against both window and display backgrounds. A test enforces this threshold.
- Increase Contrast replaces decorative secondary text and border colors with the skin's primary text color.
- MacAmp has no automatic marquee, spectrum, or transition animation, so Reduce Motion does not require an alternate rendering path.

## Manual release audit

Run this list on the oldest and newest supported macOS versions before release:

1. Enable Full Keyboard Access. Traverse each module forward and backward and confirm focus is always visible and cycles in the documented order.
2. Use Space, the Playback menu, and each focused control without a pointer. Confirm unavailable actions are skipped or disabled.
3. Enable VoiceOver. Read the player, compact player, equalizer, empty playlist, populated playlist, playing row, unavailable row, and each error state.
4. Change playback position, volume, preamp, and every EQ band with VoiceOver and confirm the announced value updates.
5. Enable Increase Contrast while MacAmp is closed, launch it, and inspect all three bundled skins at 100%, 125%, and 150%.
6. Enable Reduce Motion and confirm no content moves automatically.
7. Repeat with a third-party skin and verify its artwork does not replace native control semantics or focus rings.

The automated accessibility-tree inspection and contrast tests pass. A complete spoken VoiceOver audit remains a release-machine task.
