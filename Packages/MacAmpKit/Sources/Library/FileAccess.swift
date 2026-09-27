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
    private let allowsDirectFileAccessFallback: Bool
    private let requiresAcquiredSecurityScope: Bool

    public init() {
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        allowsDirectFileAccessFallback = !isSandboxed
        requiresAcquiredSecurityScope = isSandboxed
        if isSandboxed {
            bookmarkCreator = { url in
                try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            bookmarkResolver = { data in
                var stale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                return BookmarkResolution(url: url, isStale: stale)
            }
        } else {
            bookmarkCreator = { url in
                try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            bookmarkResolver = { data in
                var stale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                return BookmarkResolution(url: url, isStale: stale)
            }
        }
    }

    public init(
        bookmarkCreator: @escaping BookmarkCreator,
        bookmarkResolver: @escaping BookmarkResolver,
        allowsDirectFileAccessFallback: Bool = false,
        requiresAcquiredSecurityScope: Bool = false
    ) {
        self.bookmarkCreator = bookmarkCreator
        self.bookmarkResolver = bookmarkResolver
        self.allowsDirectFileAccessFallback = allowsDirectFileAccessFallback
        self.requiresAcquiredSecurityScope = requiresAcquiredSecurityScope
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
            return directResolution(for: track.lastKnownURL)
        }

        do {
            let resolution = try bookmarkResolver(bookmark)
            guard !resolution.isStale else {
                return directResolution(for: resolution.url)
            }
            let acquired = resolution.url.startAccessingSecurityScopedResource()
            guard acquired || !requiresAcquiredSecurityScope || allowsDirectAccess(to: resolution.url) else {
                return .needsReauthorization(lastKnownURL: resolution.url)
            }
            return .granted(SecurityScopedFileLease(url: resolution.url, didAcquireScope: acquired))
        } catch {
            return directResolution(for: track.lastKnownURL)
        }
    }

    private func directResolution(for url: URL) -> FileAccessResolution {
        guard allowsDirectAccess(to: url) else {
            return .needsReauthorization(lastKnownURL: url)
        }
        return .granted(SecurityScopedFileLease(url: url, didAcquireScope: false))
    }

    private func allowsDirectAccess(to url: URL) -> Bool {
        allowsDirectFileAccessFallback && FileManager.default.isReadableFile(atPath: url.path)
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
