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
    public typealias ScopeAcquirer = @Sendable (URL) -> Bool
    public typealias ScopeReleaser = @Sendable (URL) -> Void

    private let bookmarkCreator: BookmarkCreator
    private let bookmarkResolver: BookmarkResolver
    private let scopeAcquirer: ScopeAcquirer
    private let scopeReleaser: ScopeReleaser
    private let allowsDirectFileAccessFallback: Bool
    private let requiresAcquiredSecurityScope: Bool

    public init() {
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        allowsDirectFileAccessFallback = !isSandboxed
        requiresAcquiredSecurityScope = isSandboxed
        scopeAcquirer = { $0.startAccessingSecurityScopedResource() }
        scopeReleaser = { $0.stopAccessingSecurityScopedResource() }
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
        requiresAcquiredSecurityScope: Bool = false,
        scopeAcquirer: @escaping ScopeAcquirer = { $0.startAccessingSecurityScopedResource() },
        scopeReleaser: @escaping ScopeReleaser = { $0.stopAccessingSecurityScopedResource() }
    ) {
        self.bookmarkCreator = bookmarkCreator
        self.bookmarkResolver = bookmarkResolver
        self.allowsDirectFileAccessFallback = allowsDirectFileAccessFallback
        self.requiresAcquiredSecurityScope = requiresAcquiredSecurityScope
        self.scopeAcquirer = scopeAcquirer
        self.scopeReleaser = scopeReleaser
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
            let acquired = scopeAcquirer(resolution.url)
            guard acquired || !requiresAcquiredSecurityScope || allowsDirectAccess(to: resolution.url) else {
                return .needsReauthorization(lastKnownURL: resolution.url)
            }
            return .granted(SecurityScopedFileLease(
                url: resolution.url,
                didAcquireScope: acquired,
                scopeReleaser: scopeReleaser
            ))
        } catch {
            return directResolution(for: track.lastKnownURL)
        }
    }

    private func directResolution(for url: URL) -> FileAccessResolution {
        guard allowsDirectAccess(to: url) else {
            return .needsReauthorization(lastKnownURL: url)
        }
        return .granted(SecurityScopedFileLease(url: url, didAcquireScope: false, scopeReleaser: scopeReleaser))
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
    private let scopeReleaser: SecurityScopedFileAccessService.ScopeReleaser
    private var isReleased = false

    init(
        url: URL,
        didAcquireScope: Bool,
        scopeReleaser: @escaping SecurityScopedFileAccessService.ScopeReleaser
    ) {
        self.url = url
        self.didAcquireScope = didAcquireScope
        self.scopeReleaser = scopeReleaser
    }

    public func release() {
        guard !isReleased else { return }
        isReleased = true
        if didAcquireScope { scopeReleaser(url) }
    }
}
