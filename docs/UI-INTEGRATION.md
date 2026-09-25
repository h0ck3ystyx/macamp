# PlayerUI integration

September 25, 2026 · T5 handoff

`PlayerUIWindowController` is the reusable AppKit product shell. It owns Player, Equalizer, and Playlist windows but does not own playback or queue services.

## Composition

The app composition root should retain one controller for the application lifetime:

```swift
let windows = PlayerUIWindowController(playback: initialPlayback, queue: initialQueue)
windows.commandRouter = commandRouter
windows.importFeedback = { urls, replacesQueue in
    // Optional: expose import progress or accepted-file feedback.
}
windows.show()
```

`PlayerUICommandRouting` is main-actor synchronous so a UI event can leave AppKit immediately. A production adapter should start a `Task` and call the shared async `PlaybackCoordinator.send(_:)`; it must not perform decoding or file access on the main actor.

Whenever shared state changes, provide both snapshots so selected and playing rows remain distinct:

```swift
windows.update(playback: playbackSnapshot, queue: queueSnapshot)
```

The views derive all labels, transport state, seek availability, queue markers, shuffle/repeat state, and EQ values from these snapshots. There is no UI playback timer. `PlayerUIPreviewAdapter` and `PlayerUIWindowController.preview(...)` are the only placeholder-state path.

## Commands and files

The UI dispatches the shared commands for play/pause/stop/previous/next, seek, volume, shuffle, repeat, select/play, remove/reorder, and all EQ changes. File panels and file URL drops dispatch `.open` or `.append`:

- Open always replaces the queue.
- A drop on an empty Player replaces the queue; a drop on a populated Player appends.
- A drop on Playlist and its Add button append.
- `importFeedback` runs immediately before dispatch and can drive temporary accepted/importing feedback while T2 resolves folders and metadata.

The coordinator should route Finder Open With and native menu Open/Add through the same command path. UI-selected URLs are authorization events; the file service remains responsible for bookmarks and access leases.

## Skins

Call `applySkin(_:)` with a validated `ResolvedSkin`. PlayerUI consumes the six canonical color roles and retains native AppKit fallbacks. Graphite and Paper remain available through `applyPreviewSkin(_:)` for the T3 design preview. Live skin application rebuilds only window content and does not touch playback, queue, or audio services.

## Window and menu hooks

The app menu should expose:

- `openFiles(replacingQueue:)` for Open and Add
- `setModule(_:visible:)` for EQ and Playlist
- `setCompactMode(_:)` or `toggleCompactMode()`
- `resetLayout()` as an always-reachable recovery command
- `applySkin(_:)` through the skin-selection surface

Closing Player hides all modules while preserving desired secondary visibility. Dock activation calls `show()`. Closing a secondary module hides it. Quit behavior remains in the application delegate.

## Current boundary

The UI supports the prototype interactions and states, but T7 must attach real coordinator streams and queue snapshots. Search is presentation-only and never mutates playback order. Saved playlists, Undo menu wiring, skin chooser UI, scale selection, Now Playing, and media keys remain T9 or later work. The playlist uses native `NSTableView`, which is view-reusing and suitable for large queues; T11 still needs measured 10,000-row validation.
