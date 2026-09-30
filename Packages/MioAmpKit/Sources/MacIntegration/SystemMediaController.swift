@preconcurrency import MediaPlayer
import Contracts
import Foundation

@MainActor
public final class SystemMediaController: NSObject {
    private let commandCenter = MPRemoteCommandCenter.shared()
    private let sendCommand: @Sendable (PlayerCommand) -> Void
    private var lastPlaybackState: PlaybackState = .idle

    public init(sendCommand: @escaping @Sendable (PlayerCommand) -> Void) {
        self.sendCommand = sendCommand
        super.init()
        commandCenter.playCommand.addTarget(self, action: #selector(play(_:)))
        commandCenter.pauseCommand.addTarget(self, action: #selector(pause(_:)))
        commandCenter.togglePlayPauseCommand.addTarget(self, action: #selector(toggle(_:)))
        commandCenter.stopCommand.addTarget(self, action: #selector(stop(_:)))
        commandCenter.nextTrackCommand.addTarget(self, action: #selector(next(_:)))
        commandCenter.previousTrackCommand.addTarget(self, action: #selector(previous(_:)))
        commandCenter.changePlaybackPositionCommand.addTarget(self, action: #selector(changePosition(_:)))
    }

    public func update(playback: PlaybackSnapshot, queue: QueueSnapshot) {
        lastPlaybackState = playback.state
        guard let currentID = playback.currentEntryID ?? queue.playingEntryID,
              let entry = queue.entries.first(where: { $0.id == currentID }),
              let track = queue.tracks[entry.trackID] else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }

        let metadata: TrackMetadata?
        if case .loaded(let value) = track.metadata { metadata = value } else { metadata = nil }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata?.title ?? track.lastKnownURL.deletingPathExtension().lastPathComponent,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playback.position,
            MPNowPlayingInfoPropertyPlaybackRate: playback.state == .playing ? 1.0 : 0.0,
        ]
        if let artist = metadata?.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = metadata?.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let duration = playback.duration ?? metadata?.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        switch playback.state {
        case .playing: MPNowPlayingInfoCenter.default().playbackState = .playing
        case .paused: MPNowPlayingInfoCenter.default().playbackState = .paused
        default: MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }

    @objc private func play(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        sendCommand(.play); return .success
    }

    @objc private func pause(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        sendCommand(.pause); return .success
    }

    @objc private func toggle(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        sendCommand(lastPlaybackState == .playing ? .pause : .play); return .success
    }

    @objc private func stop(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        sendCommand(.stop); return .success
    }

    @objc private func next(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        sendCommand(.next); return .success
    }

    @objc private func previous(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        sendCommand(.previous); return .success
    }

    @objc private func changePosition(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
        sendCommand(.seek(to: event.positionTime)); return .success
    }
}
