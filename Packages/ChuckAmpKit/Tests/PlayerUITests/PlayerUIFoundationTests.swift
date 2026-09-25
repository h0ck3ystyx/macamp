@testable import PlayerUI
import AppKit
import Contracts
import Testing

@MainActor @Test func playerUITargetLoads() {
    #expect(PlayerUIModule.isPrototypeImplemented)
    #expect(PlayerUIWindowController.defaultPlayerSize == NSSize(width: 360, height: 160))
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

@MainActor @Test func resetLayoutKeepsRequiredModulesRecoverable() {
    let controller = PlayerUIWindowController()
    let layout = controller.currentLayout()
    #expect(layout.isCompact == false)
    #expect(layout.modules.first(where: { $0.module == .player })?.isVisible == true)
    #expect(layout.modules.first(where: { $0.module == .playlist })?.isVisible == true)
    #expect(layout.modules.first(where: { $0.module == .equalizer })?.isVisible == false)
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
    #expect(labels.contains("Play or pause"))
    #expect(labels.contains("Stop"))
    #expect(labels.contains("Next track"))
    #expect(labels.contains("Open audio"))
}

@MainActor private func allSubviews(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(allSubviews)
}
