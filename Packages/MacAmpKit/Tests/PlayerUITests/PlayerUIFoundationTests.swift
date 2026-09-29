@testable import PlayerUI
import AppKit
import Contracts
import Testing

@MainActor @Test func playerUITargetLoads() {
    #expect(PlayerUIModule.isPrototypeImplemented)
    #expect(PlayerUIWindowController.defaultPlayerSize == NSSize(width: 360, height: 160))
    #expect(PlayerUIWindowController.defaultEqualizerSize == NSSize(width: 360, height: 200))
    #expect(PlayerUIWindowController.defaultPlaylistSize == NSSize(width: 360, height: 260))
    #expect(PlayerUIWindowController.compactPlayerSize == NSSize(width: 360, height: 40))
}

@Test func secondaryWindowSnapsBelowPlayerWithinThreshold() {
    let player = NSRect(x: 100, y: 500, width: 360, height: 160)
    let moving = NSRect(x: 106, y: 342, width: 360, height: 160)
    let snapped = WindowSnapGeometry.snappedFrame(moving: moving, to: player, threshold: 10)
    #expect(snapped?.origin == NSPoint(x: 100, y: 340))
}

@Test func secondaryWindowDoesNotSnapOutsideThreshold() {
    let player = NSRect(x: 100, y: 500, width: 360, height: 160)
    let moving = NSRect(x: 125, y: 310, width: 360, height: 160)
    #expect(WindowSnapGeometry.snappedFrame(moving: moving, to: player, threshold: 10) == nil)
}

@Test func previewSkinsIncludeGraphiteAndPaper() {
    #expect(PlayerUISkinPreview.allCases == [.graphite, .paper])
}

@Test func interfaceScaleEnlargesThemeTypography() {
    let normal = PlayerUITheme(.graphite)
    let enlarged = PlayerUITheme(.graphite, scale: 1.5)
    #expect(enlarged.trackFont.pointSize == normal.trackFont.pointSize * 1.5)
    #expect(enlarged.technicalFont.pointSize == normal.technicalFont.pointSize * 1.5)
    #expect(enlarged.controlFont.pointSize == normal.controlFont.pointSize * 1.5)
}

@Test func increasedContrastOverridesDecorativeSkinColors() {
    let normal = PlayerUITheme(.graphite, increaseContrast: false)
    let increased = PlayerUITheme(.graphite, increaseContrast: true)
    #expect(increased.secondaryText == increased.text)
    #expect(increased.border == increased.text)
    #expect(normal.secondaryText != normal.text)
}

@MainActor @Test func resetLayoutKeepsRequiredModulesRecoverable() {
    let track = TrackReference(
        lastKnownURL: URL(fileURLWithPath: "/music/long.mp3"),
        metadata: .loaded(TrackMetadata(title: "A very long restored track title that must truncate instead of resizing the player window", artist: "An equally long artist name"))
    )
    let entry = QueueEntry(trackID: track.id)
    let queue = QueueSnapshot(entries: [entry], tracks: [track.id: track], playingEntryID: entry.id)
    let controller = PlayerUIWindowController(playback: PlaybackSnapshot(state: .paused, currentEntryID: entry.id), queue: queue)
    let layout = controller.currentLayout()
    #expect(layout.isCompact == false)
    #expect(layout.modules.first(where: { $0.module == .player })?.isVisible == true)
    #expect(layout.modules.first(where: { $0.module == .playlist })?.isVisible == true)
    #expect(layout.modules.first(where: { $0.module == .equalizer })?.isVisible == false)
    #expect(layout.modules.first(where: { $0.module == .player })?.frame.width == 360)
    #expect((layout.modules.first(where: { $0.module == .player })?.frame.height ?? 0) > 160)
    #expect(layout.modules.first(where: { $0.module == .playlist })?.frame.width == 360)
}

@MainActor @Test func validLayoutRestoresScaleCompactModeAndVisibility() {
    let controller = PlayerUIWindowController()
    let group = UUID()
    let layout = WindowLayout(
        scale: 1.25,
        isCompact: true,
        modules: [
            ModuleLayout(module: .player, frame: WindowRect(x: 120, y: 500, width: 450, height: 50), isVisible: true, groupID: group),
            ModuleLayout(module: .equalizer, frame: WindowRect(x: 120, y: 300, width: 450, height: 200), isVisible: true, groupID: group),
            ModuleLayout(module: .playlist, frame: WindowRect(x: 120, y: 100, width: 450, height: 200), isVisible: false, groupID: group),
        ]
    )
    controller.applyLayout(layout)
    let restored = controller.currentLayout()
    #expect(restored.scale == 1.25)
    #expect(restored.isCompact)
    #expect(restored.modules.first(where: { $0.module == .player })?.isVisible == true)
    #expect(restored.modules.first(where: { $0.module == .equalizer })?.isVisible == true)
    #expect(restored.modules.first(where: { $0.module == .playlist })?.isVisible == false)
    #expect((restored.modules.first(where: { $0.module == .equalizer })?.frame.height ?? 0) > 250)
    #expect((restored.modules.first(where: { $0.module == .playlist })?.frame.height ?? 0) > 225)
    controller.setCompactMode(false)
    let expandedPlayer = controller.currentLayout().modules.first(where: { $0.module == .player })?.frame
    #expect(expandedPlayer?.width == 450)
    #expect((expandedPlayer?.height ?? 0) > 200)
}

@MainActor @Test func playlistRefreshKeepsUserResizedFrame() throws {
    let controller = PlayerUIWindowController()
    var layout = controller.currentLayout()
    let playlistIndex = try #require(layout.modules.firstIndex(where: { $0.module == .playlist }))
    layout.modules[playlistIndex].frame.width += 180
    layout.modules[playlistIndex].frame.height += 140
    controller.applyLayout(layout)
    let expandedFrame = try #require(controller.currentLayout().modules.first(where: { $0.module == .playlist })?.frame)

    let track = TrackReference(lastKnownURL: URL(fileURLWithPath: "/music/selection.mp3"))
    let entry = QueueEntry(trackID: track.id)
    var queue = QueueSnapshot(entries: [entry], tracks: [track.id: track])
    controller.update(playback: PlaybackSnapshot(), queue: queue)
    queue.selectedEntryID = entry.id
    controller.update(playback: PlaybackSnapshot(), queue: queue)

    #expect(controller.currentLayout().modules.first(where: { $0.module == .playlist })?.frame == expandedFrame)
    controller.applyPreviewSkin(.paper)
    #expect(controller.currentLayout().modules.first(where: { $0.module == .playlist })?.frame == expandedFrame)
}

@Test func interfaceScaleReattachesConnectedFrames() throws {
    let oldPlayer = NSRect(x: 100, y: 700, width: 360, height: 192)
    let oldEqualizer = NSRect(x: 100, y: 508, width: 360, height: 192)
    let newPlayer = NSRect(x: 100, y: 660, width: 450, height: 232)
    let newEqualizer = try #require(WindowScaleGeometry.attachedFrame(
        movingOld: oldEqualizer,
        movingSize: NSSize(width: 450, height: 232),
        anchorOld: oldPlayer,
        anchorNew: newPlayer
    ))
    #expect(newEqualizer == NSRect(x: 100, y: 428, width: 450, height: 232))
}

@MainActor @Test func hidingEqualizerClosesGapInConnectedStack() throws {
    let controller = PlayerUIWindowController()
    controller.setModule(.equalizer, visible: true)
    let shown = controller.currentLayout()
    let shownPlayer = try #require(shown.modules.first(where: { $0.module == .player })?.frame)
    let shownEqualizer = try #require(shown.modules.first(where: { $0.module == .equalizer })?.frame)
    let shownPlaylist = try #require(shown.modules.first(where: { $0.module == .playlist })?.frame)
    #expect(shownPlaylist.y + shownPlaylist.height == shownEqualizer.y)
    #expect(shownEqualizer.y + shownEqualizer.height == shownPlayer.y)

    controller.setModule(.equalizer, visible: false)
    let hidden = controller.currentLayout()
    let hiddenPlayer = try #require(hidden.modules.first(where: { $0.module == .player })?.frame)
    let hiddenPlaylist = try #require(hidden.modules.first(where: { $0.module == .playlist })?.frame)
    #expect(hiddenPlaylist.y + hiddenPlaylist.height == hiddenPlayer.y)
    #expect(hidden.modules.first(where: { $0.module == .equalizer })?.isVisible == false)
}

@Test func legacyEqualizerGrowthReflowsConnectedStackGeometry() throws {
    let oldPlayer = NSRect(x: 100, y: 600, width: 360, height: 192)
    let oldEqualizer = NSRect(x: 100, y: 408, width: 360, height: 192)
    let oldPlaylist = NSRect(x: 100, y: 76, width: 360, height: 332)
    let newEqualizer = try #require(WindowScaleGeometry.attachedFrame(
        movingOld: oldEqualizer,
        movingSize: NSSize(width: 360, height: 232),
        anchorOld: oldPlayer,
        anchorNew: oldPlayer
    ))
    let newPlaylist = try #require(WindowScaleGeometry.attachedFrame(
        movingOld: oldPlaylist,
        movingSize: oldPlaylist.size,
        anchorOld: oldEqualizer,
        anchorNew: newEqualizer
    ))
    #expect(newEqualizer.maxY == oldPlayer.minY)
    #expect(newPlaylist.maxY == newEqualizer.minY)
}

@Test func presentationDistinguishesSelectedPlayingAndUnavailableRows() {
    let playingTrack = TrackID(); let missingTrack = TrackID()
    let playing = QueueEntry(trackID: playingTrack); let missing = QueueEntry(trackID: missingTrack)
    let queue = QueueSnapshot(
        entries: [playing, missing],
        tracks: [
            playingTrack: TrackReference(lastKnownURL: URL(fileURLWithPath: "/music/a.flac"), metadata: .loaded(TrackMetadata(title: "A", artist: "Artist", duration: 60))),
            missingTrack: TrackReference(lastKnownURL: URL(fileURLWithPath: "/music/missing.mp3"), metadata: .unavailable(reason: "Missing file")),
        ],
        selectedEntryID: missing.id,
        playingEntryID: playing.id
    )
    let model = PlayerUIStateModel(playback: PlaybackSnapshot(state: .paused, currentEntryID: playing.id), queue: queue)
    #expect(model.rows[0].isPlaying)
    #expect(!model.rows[0].isSelected)
    #expect(model.rows[1].isSelected)
    #expect(model.rows[1].isUnavailable)
    #expect(model.statusText == "PAUSED")
    var filtered = model
    filtered.filterText = "album only"
    var withAlbum = queue
    withAlbum.tracks[playingTrack]?.metadata = .loaded(TrackMetadata(title: "A", artist: "Artist", album: "Album Only", duration: 60))
    filtered.queue = withAlbum
    #expect(filtered.rows.map(\.id) == [playing.id])
}

@Test func interactionCommandsClampAndCycle() {
    let playback = PlaybackSnapshot(state: .playing, position: 20, duration: 100, volume: 0.5, equalizer: EQSettings(isBypassed: false))
    let model = PlayerUIStateModel(playback: playback, queue: QueueSnapshot(isShuffled: false, repeatMode: .off))
    #expect(model.playPauseCommand == .pause)
    #expect(model.seekCommand(fraction: 1.5) == .seek(to: 100))
    #expect(model.volumeCommand(-1) == .setVolume(0))
    #expect(model.nextRepeatMode == .all)
    #expect(model.equalizerCommand(band: 0, gain: 20) == .setEqualizer(EQSettings(isBypassed: false, bandGains: [12, 0, 0, 0, 0, 0, 0, 0, 0, 0])))
}

@MainActor private final class RecordingRouter: PlayerUICommandRouting {
    var commands: [PlayerCommand] = []
    func send(_ command: PlayerCommand) { commands.append(command) }
}

@MainActor @Test func controllerRoutesCommandsAndDropIntent() {
    let router = RecordingRouter(); let controller = PlayerUIWindowController(); controller.commandRouter = router
    var feedback: (Int, Bool)?
    controller.importFeedback = { feedback = ($0.count, $1) }
    controller.dispatch(.next)
    controller.receiveFiles([URL(fileURLWithPath: "/tmp/song.mp3")], replacingQueue: false)
    #expect(router.commands == [.next, .append([URL(fileURLWithPath: "/tmp/song.mp3")])])
    #expect(feedback?.0 == 1)
    #expect(feedback?.1 == false)
}

@MainActor @Test func primaryIconControlsHaveAccessibleNames() {
    let noOp = PlayerUIActions(send: { _ in }, compact: {}, showEqualizer: {}, showPlaylist: {}, importFiles: { _ in }, receiveFiles: { _, _ in }, search: { _ in })
    let controller = PlayerViewController(theme: PlayerUITheme(.graphite), model: PlayerUIStateModel(), actions: noOp)
    _ = controller.view
    let labels = allSubviews(of: controller.view).compactMap { ($0 as? NSButton)?.accessibilityLabel() }
    #expect(labels.contains("Previous track"))
    #expect(labels.contains("Play"))
    #expect(labels.contains("Stop"))
    #expect(labels.contains("Next track"))
    #expect(labels.contains("Open audio"))
}

@MainActor @Test func playerAccessibilityReflectsPlaybackStateAndReadableValues() throws {
    let noOp = PlayerUIActions(send: { _ in }, compact: {}, showEqualizer: {}, showPlaylist: {}, importFiles: { _ in }, receiveFiles: { _, _ in }, search: { _ in })
    let track = TrackReference(lastKnownURL: URL(fileURLWithPath: "/music/accessibility.mp3"))
    let entry = QueueEntry(trackID: track.id)
    let queue = QueueSnapshot(entries: [entry], tracks: [track.id: track], playingEntryID: entry.id)
    let playback = PlaybackSnapshot(state: .playing, currentEntryID: entry.id, position: 30, duration: 120, volume: 0.42)
    let controller = PlayerViewController(theme: PlayerUITheme(.graphite), model: PlayerUIStateModel(playback: playback, queue: queue), actions: noOp)
    _ = controller.view
    let controls = allSubviews(of: controller.view).compactMap { $0 as? NSControl }
    let pause = try #require(controls.first(where: { $0.accessibilityLabel() == "Pause" }) as? NSButton)
    let position = try #require(controls.first(where: { $0.accessibilityLabel() == "Playback position" }) as? NSSlider)
    let volume = try #require(controls.first(where: { $0.accessibilityLabel() == "Volume" }) as? NSSlider)
    #expect(pause.isEnabled)
    #expect(position.accessibilityValue() as? String == "00:30 of 02:00")
    #expect(volume.accessibilityValue() as? String == "42 percent")
}

@MainActor @Test func playlistMutationControlsMatchSelectionState() throws {
    let noOp = PlayerUIActions(send: { _ in }, compact: {}, showEqualizer: {}, showPlaylist: {}, importFiles: { _ in }, receiveFiles: { _, _ in }, search: { _ in })
    let firstTrack = TrackReference(lastKnownURL: URL(fileURLWithPath: "/music/first.mp3"))
    let secondTrack = TrackReference(lastKnownURL: URL(fileURLWithPath: "/music/second.mp3"))
    let first = QueueEntry(trackID: firstTrack.id); let second = QueueEntry(trackID: secondTrack.id)
    let queue = QueueSnapshot(entries: [first, second], tracks: [firstTrack.id: firstTrack, secondTrack.id: secondTrack], selectedEntryID: first.id)
    let controller = PlaylistViewController(theme: PlayerUITheme(.graphite), model: PlayerUIStateModel(queue: queue), actions: noOp)
    _ = controller.view
    let buttons = allSubviews(of: controller.view).compactMap { $0 as? NSButton }
    #expect(try #require(buttons.first(where: { $0.accessibilityLabel() == "Remove selected tracks" })).isEnabled)
    #expect(try #require(buttons.first(where: { $0.accessibilityLabel() == "Clear playlist" })).isEnabled)
    #expect(!(try #require(buttons.first(where: { $0.accessibilityLabel() == "Move selected track up" }))).isEnabled)
    #expect(try #require(buttons.first(where: { $0.accessibilityLabel() == "Move selected track down" })).isEnabled)
}

@MainActor @Test func playerDefinesExplicitKeyboardFocusOrder() throws {
    let noOp = PlayerUIActions(send: { _ in }, compact: {}, showEqualizer: {}, showPlaylist: {}, importFiles: { _ in }, receiveFiles: { _, _ in }, search: { _ in })
    let track = TrackReference(lastKnownURL: URL(fileURLWithPath: "/music/focus.mp3"))
    let entry = QueueEntry(trackID: track.id)
    let queue = QueueSnapshot(entries: [entry], tracks: [track.id: track])
    let controller = PlayerViewController(theme: PlayerUITheme(.graphite), model: PlayerUIStateModel(queue: queue), actions: noOp)
    _ = controller.view
    let controls = allSubviews(of: controller.view).compactMap { $0 as? NSControl }
    let position = try #require(controls.first(where: { $0.accessibilityLabel() == "Playback position" }))
    let previous = try #require(controls.first(where: { $0.accessibilityLabel() == "Previous track" }))
    let play = try #require(controls.first(where: { $0.accessibilityLabel() == "Play" }))
    #expect(position.nextKeyView === previous)
    #expect(previous.nextKeyView === play)
}

@MainActor @Test func graphiteButtonsHaveExplicitVisibleStyling() throws {
    let noOp = PlayerUIActions(send: { _ in }, compact: {}, showEqualizer: {}, showPlaylist: {}, importFiles: { _ in }, receiveFiles: { _, _ in }, search: { _ in })
    let controller = PlayerViewController(theme: PlayerUITheme(.graphite), model: PlayerUIStateModel(), actions: noOp)
    _ = controller.view
    let buttons = allSubviews(of: controller.view).compactMap { $0 as? NSButton }
    let open = try #require(buttons.first(where: { $0.accessibilityLabel() == "Open audio" }))
    #expect(!open.isBordered)
    #expect(open.layer?.backgroundColor != nil)
    #expect(open.layer?.borderColor != nil)
    #expect(open.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) is NSColor)
}

@MainActor @Test func transportArtworkOwnsOneFullSizeButtonFace() {
    let controller = ThemedViewController(theme: PlayerUITheme(.graphite))
    let image = NSImage(size: NSSize(width: 28, height: 28))
    let button = controller.button("▶︎", label: "Play", image: image, action: {})
    #expect(button.title.isEmpty)
    #expect(button.attributedTitle.length == 0)
    #expect(button.imagePosition == .imageOnly)
    #expect(button.image?.size == NSSize(width: 34, height: 28))
    #expect(button.layer?.borderWidth == 0)
}

@MainActor private func allSubviews(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(allSubviews)
}
