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
        let flac = url.pathExtension.caseInsensitiveCompare("flac") == .orderedSame
            ? try? FLACVorbisCommentReader.read(from: url)
            : nil
        let title = try await firstString(.commonIdentifierTitle, in: common) ?? flac?.title
        let artist = try await firstString(.commonIdentifierArtist, in: common) ?? flac?.artist
        let album = try await firstString(.commonIdentifierAlbumName, in: common) ?? flac?.album
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

struct FLACVorbisComments: Equatable, Sendable {
    var title: String?
    var artist: String?
    var album: String?
}

enum FLACVorbisCommentReader {
    private static let maximumMetadataBytes = 16 * 1_024 * 1_024
    private static let maximumCommentBlockBytes = 4 * 1_024 * 1_024

    static func read(from url: URL) throws -> FLACVorbisComments? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var offset: UInt64 = 0
        let prefix = try handle.read(upToCount: 10) ?? Data()
        if prefix.count == 10, prefix.starts(with: Data("ID3".utf8)) {
            let sizeBytes = prefix[6..<10]
            guard sizeBytes.allSatisfy({ $0 & 0x80 == 0 }) else { return nil }
            let size = sizeBytes.reduce(0) { ($0 << 7) | Int($1) }
            let hasFooter = prefix[5] & 0x10 != 0
            offset = UInt64(10 + size + (hasFooter ? 10 : 0))
        }
        try handle.seek(toOffset: offset)
        guard try handle.read(upToCount: 4) == Data("fLaC".utf8) else { return nil }

        var inspected = 0
        while inspected <= maximumMetadataBytes {
            guard let header = try handle.read(upToCount: 4), header.count == 4 else { return nil }
            let isLast = header[0] & 0x80 != 0
            let type = header[0] & 0x7f
            let length = (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])
            inspected += 4 + length
            guard inspected <= maximumMetadataBytes else { return nil }

            if type == 4 {
                guard length <= maximumCommentBlockBytes,
                      let payload = try handle.read(upToCount: length), payload.count == length else { return nil }
                return parse(payload)
            }
            try handle.seek(toOffset: handle.offsetInFile + UInt64(length))
            if isLast { return nil }
        }
        return nil
    }

    private static func parse(_ data: Data) -> FLACVorbisComments? {
        var cursor = 0
        guard let vendorLength = readUInt32LE(data, cursor: &cursor),
              vendorLength <= data.count - cursor else { return nil }
        cursor += vendorLength
        guard let commentCount = readUInt32LE(data, cursor: &cursor), commentCount <= 65_536 else { return nil }

        var fields: [String: String] = [:]
        for _ in 0..<commentCount {
            guard let length = readUInt32LE(data, cursor: &cursor),
                  length <= data.count - cursor else { return nil }
            let value = String(decoding: data[cursor..<(cursor + length)], as: UTF8.self)
            cursor += length
            guard let separator = value.firstIndex(of: "=") else { continue }
            let key = String(value[..<separator]).uppercased()
            let content = String(value[value.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if fields[key] == nil, !content.isEmpty { fields[key] = content }
        }
        let result = FLACVorbisComments(title: fields["TITLE"], artist: fields["ARTIST"], album: fields["ALBUM"])
        return result.title == nil && result.artist == nil && result.album == nil ? nil : result
    }

    private static func readUInt32LE(_ data: Data, cursor: inout Int) -> Int? {
        guard cursor <= data.count - 4 else { return nil }
        let value = Int(data[cursor])
            | (Int(data[cursor + 1]) << 8)
            | (Int(data[cursor + 2]) << 16)
            | (Int(data[cursor + 3]) << 24)
        cursor += 4
        return value
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
                if let playlistFormat = PortablePlaylistFormat(rawValue: url.pathExtension.lowercased()) {
                    let playlist = try PortablePlaylistCodec().decode(
                        Data(contentsOf: url),
                        format: playlistFormat,
                        relativeTo: url.deletingLastPathComponent()
                    )
                    candidates.append(contentsOf: playlist.localURLs)
                    failures.append(contentsOf: playlist.issues.compactMap { issue in
                        guard issue.kind == .unsupportedRemoteURL else { return nil }
                        return FileImportFailure(
                            url: url,
                            reason: "Unsupported remote playlist entry at line \(issue.line ?? 0): \(issue.value)"
                        )
                    })
                } else {
                    candidates.append(contentsOf: try expand(url))
                }
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
