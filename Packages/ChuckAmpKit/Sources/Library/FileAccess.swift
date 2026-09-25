import Contracts
import Foundation

public enum FileAccessError: Error, Equatable, Sendable {
    case missingFile(URL)
    case bookmarkCreationFailed(String)
}

public struct BookmarkResolution: Sendable {
    public var url: URL
    public var isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

public actor SecurityScopedFileAccessService: FileAccessService {
    public typealias BookmarkCreator = @Sendable (URL) throws -> Data
    public typealias BookmarkResolver = @Sendable (Data) throws -> BookmarkResolution

    private let bookmarkCreator: BookmarkCreator
    private let bookmarkResolver: BookmarkResolver

    public init() {
        self.bookmarkCreator = { url in
            try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        self.bookmarkResolver = { data in
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return BookmarkResolution(url: url, isStale: stale)
        }
    }

    public init(bookmarkCreator: @escaping BookmarkCreator, bookmarkResolver: @escaping BookmarkResolver) {
        self.bookmarkCreator = bookmarkCreator
        self.bookmarkResolver = bookmarkResolver
    }

    public func bookmark(for url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileAccessError.missingFile(url)
        }
        do {
            return try bookmarkCreator(url)
        } catch {
            throw FileAccessError.bookmarkCreationFailed(error.localizedDescription)
        }
    }

    public func resolve(_ track: TrackReference) throws -> FileAccessResolution {
        guard let bookmark = track.securityScopedBookmark else {
            guard FileManager.default.fileExists(atPath: track.lastKnownURL.path) else {
                return .needsReauthorization(lastKnownURL: track.lastKnownURL)
            }
            let acquired = track.lastKnownURL.startAccessingSecurityScopedResource()
            return .granted(SecurityScopedFileLease(url: track.lastKnownURL, didAcquireScope: acquired))
        }

        do {
            let resolution = try bookmarkResolver(bookmark)
            guard !resolution.isStale, FileManager.default.fileExists(atPath: resolution.url.path) else {
                return .needsReauthorization(lastKnownURL: resolution.url)
            }
            let acquired = resolution.url.startAccessingSecurityScopedResource()
            return .granted(SecurityScopedFileLease(url: resolution.url, didAcquireScope: acquired))
        } catch {
            return .needsReauthorization(lastKnownURL: track.lastKnownURL)
        }
    }

    public func reauthorize(_ track: TrackReference, at url: URL) throws -> TrackReference {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileAccessError.missingFile(url)
        }
        return TrackReference(
            id: track.id,
            lastKnownURL: url,
            securityScopedBookmark: try bookmark(for: url),
            metadata: track.metadata
        )
    }
}

public actor SecurityScopedFileLease: FileAccessLease {
    public nonisolated let url: URL
    private let didAcquireScope: Bool
    private var isReleased = false

    init(url: URL, didAcquireScope: Bool) {
        self.url = url
        self.didAcquireScope = didAcquireScope
    }

    public func release() {
        guard !isReleased else { return }
        isReleased = true
        if didAcquireScope { url.stopAccessingSecurityScopedResource() }
    }
}
