import AVFoundation
import Contracts
import Foundation

public struct FileImportFailure: Error, Equatable, Sendable {
    public var url: URL
    public var reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }
}

public struct FileImportResult: Equatable, Sendable {
    public var tracks: [TrackReference]
    public var failures: [FileImportFailure]

    public init(tracks: [TrackReference], failures: [FileImportFailure]) {
        self.tracks = tracks
        self.failures = failures
    }
}

public protocol TrackMetadataLoading: Sendable {
    func metadata(for url: URL) async throws -> TrackMetadata
}

public actor AVFoundationMetadataLoader: TrackMetadataLoading {
    public init() {}

    public func metadata(for url: URL) async throws -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let common = try await asset.load(.commonMetadata)
        let title = try await firstString(.commonIdentifierTitle, in: common)
        let artist = try await firstString(.commonIdentifierArtist, in: common)
        let album = try await firstString(.commonIdentifierAlbumName, in: common)
        let seconds = duration.seconds
        let audioFile = try? AVAudioFile(forReading: url)
        let format = audioFile?.processingFormat
        let pathCodec = url.pathExtension.isEmpty ? nil : url.pathExtension.uppercased()
        return TrackMetadata(
            title: title,
            artist: artist,
            album: album,
            duration: seconds.isFinite ? seconds : nil,
            codec: pathCodec,
            sampleRate: format?.sampleRate,
            channelCount: format.map { Int($0.channelCount) }
        )
    }

    private func firstString(_ identifier: AVMetadataIdentifier, in items: [AVMetadataItem]) async throws -> String? {
        guard let item = items.first(where: { $0.identifier == identifier }) else { return nil }
        return try await item.load(.stringValue)
    }
}

public actor FileImportService {
    public static let supportedExtensions: Set<String> = [
        "aac", "aif", "aiff", "alac", "flac", "m4a", "mp3", "mp4", "oga", "ogg", "opus", "wav"
    ]

    private let access: any FileAccessService
    private let metadataLoader: any TrackMetadataLoading

    public init(
        access: any FileAccessService = SecurityScopedFileAccessService(),
        metadataLoader: any TrackMetadataLoading = AVFoundationMetadataLoader()
    ) {
        self.access = access
        self.metadataLoader = metadataLoader
    }

    /// Expands folders recursively, naturally sorts their relative paths, and retains the
    /// order of top-level selections. Metadata work is concurrent but results remain ordered.
    public func importURLs(_ urls: [URL]) async -> FileImportResult {
        var candidates: [URL] = []
        var failures: [FileImportFailure] = []
        for url in urls {
            do {
                candidates.append(contentsOf: try expand(url))
            } catch {
                failures.append(FileImportFailure(url: url, reason: error.localizedDescription))
            }
        }

        let access = self.access
        let loader = self.metadataLoader
        var loaded: [(Int, Result<TrackReference, FileImportFailure>)] = []
        let maximumConcurrentLoads = 8
        for batchStart in stride(from: 0, to: candidates.count, by: maximumConcurrentLoads) {
            let batchEnd = min(batchStart + maximumConcurrentLoads, candidates.count)
            let batch = await withTaskGroup(of: (Int, Result<TrackReference, FileImportFailure>).self) { group in
                for index in batchStart..<batchEnd {
                    let url = candidates[index]
                    group.addTask {
                        do {
                            let bookmark = try await access.bookmark(for: url)
                            var track = TrackReference(lastKnownURL: url, securityScopedBookmark: bookmark)
                            do {
                                track.metadata = .loaded(try await loader.metadata(for: url))
                            } catch {
                                track.metadata = .unavailable(reason: error.localizedDescription)
                            }
                            return (index, .success(track))
                        } catch {
                            return (index, .failure(FileImportFailure(url: url, reason: error.localizedDescription)))
                        }
                    }
                }
                var values: [(Int, Result<TrackReference, FileImportFailure>)] = []
                for await value in group { values.append(value) }
                return values
            }
            loaded.append(contentsOf: batch)
        }
        loaded.sort { $0.0 < $1.0 }

        var tracks: [TrackReference] = []
        for (_, result) in loaded {
            switch result {
            case .success(let track): tracks.append(track)
            case .failure(let failure): failures.append(failure)
            }
        }
        return FileImportResult(tracks: tracks, failures: failures)
    }

    private func expand(_ url: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FileAccessError.missingFile(url)
        }
        if !isDirectory.boolValue {
            return Self.supportedExtensions.contains(url.pathExtension.lowercased()) ? [url] : []
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let files = enumerator.compactMap { $0 as? URL }.filter {
            Self.supportedExtensions.contains($0.pathExtension.lowercased())
        }
        return files.sorted { lhs, rhs in
            lhs.path.compare(rhs.path, options: [.numeric, .caseInsensitive], range: nil, locale: Locale(identifier: "en_US_POSIX")) == .orderedAscending
        }
    }
}
