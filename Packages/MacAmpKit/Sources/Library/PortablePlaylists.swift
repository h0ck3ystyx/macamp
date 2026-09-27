import Contracts
import Foundation

public enum PortablePlaylistFormat: String, Sendable {
    case m3u
    case m3u8
    case pls
}

public struct PlaylistImportIssue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case unsupportedRemoteURL
        case missingLocalFile
        case malformedEntry
        case unsupportedEncoding
    }

    public var line: Int?
    public var value: String
    public var kind: Kind

    public init(line: Int?, value: String, kind: Kind) {
        self.line = line
        self.value = value
        self.kind = kind
    }
}

public struct PortablePlaylistImportResult: Equatable, Sendable {
    /// Local entries stay in source order, including paths which need Locate/Reauthorize.
    public var localURLs: [URL]
    public var issues: [PlaylistImportIssue]

    public init(localURLs: [URL] = [], issues: [PlaylistImportIssue] = []) {
        self.localURLs = localURLs
        self.issues = issues
    }
}

public enum PortablePlaylistError: Error, Equatable, Sendable {
    case unsupportedFormat(String)
    case unreadableEncoding
    case malformedPLS
}

public struct PortablePlaylistCodec: Sendable {
    public init() {}

    public func importPlaylist(at url: URL) throws -> PortablePlaylistImportResult {
        let format = try format(for: url)
        let data = try Data(contentsOf: url)
        return try decode(data, format: format, relativeTo: url.deletingLastPathComponent())
    }

    public func decode(
        _ data: Data,
        format: PortablePlaylistFormat,
        relativeTo baseURL: URL
    ) throws -> PortablePlaylistImportResult {
        let text: String
        switch format {
        case .m3u8:
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw PortablePlaylistError.unreadableEncoding
            }
            text = decoded.removingUTF8BOM
        case .m3u, .pls:
            if let decoded = String(data: data, encoding: .utf8) {
                text = decoded.removingUTF8BOM
            } else if let decoded = String(data: data, encoding: .isoLatin1) {
                text = decoded
            } else {
                throw PortablePlaylistError.unreadableEncoding
            }
        }

        switch format {
        case .m3u, .m3u8:
            return decodeM3U(text, relativeTo: baseURL)
        case .pls:
            return try decodePLS(text, relativeTo: baseURL)
        }
    }

    public func encodeM3U(
        urls: [URL],
        format: PortablePlaylistFormat,
        relativeTo baseURL: URL? = nil
    ) throws -> Data {
        guard format == .m3u || format == .m3u8 else {
            throw PortablePlaylistError.unsupportedFormat(format.rawValue)
        }
        var lines = ["#EXTM3U"]
        lines.append(contentsOf: urls.map { portablePath(for: $0, relativeTo: baseURL) })
        // MacAmp writes UTF-8 for both extensions. M3U8 requires it; UTF-8 M3U avoids
        // locale-dependent data loss while the importer retains an ISO-8859-1 fallback.
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    public func exportM3U(urls: [URL], to destination: URL, relativePaths: Bool = true) throws {
        let format = try format(for: destination)
        let base = relativePaths ? destination.deletingLastPathComponent() : nil
        let data = try encodeM3U(urls: urls, format: format, relativeTo: base)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: [.atomic])
    }

    private func format(for url: URL) throws -> PortablePlaylistFormat {
        guard let format = PortablePlaylistFormat(rawValue: url.pathExtension.lowercased()) else {
            throw PortablePlaylistError.unsupportedFormat(url.pathExtension)
        }
        return format
    }

    private func decodeM3U(_ text: String, relativeTo baseURL: URL) -> PortablePlaylistImportResult {
        var result = PortablePlaylistImportResult()
        for (offset, rawLine) in text.linesPreservingEmpty.enumerated() {
            let value = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.hasPrefix("#") else { continue }
            append(value, line: offset + 1, relativeTo: baseURL, result: &result)
        }
        return result
    }

    private func decodePLS(_ text: String, relativeTo baseURL: URL) throws -> PortablePlaylistImportResult {
        var sawHeader = false
        var entries: [(number: Int, line: Int, value: String)] = []
        for (offset, rawLine) in text.linesPreservingEmpty.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(";") else { continue }
            if line.caseInsensitiveCompare("[playlist]") == .orderedSame {
                sawHeader = true
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if key.lowercased().hasPrefix("file"),
               let number = Int(key.dropFirst(4)), number > 0 {
                entries.append((number, lineNumber, value))
            }
        }
        guard sawHeader else { throw PortablePlaylistError.malformedPLS }
        entries.sort { lhs, rhs in
            lhs.number == rhs.number ? lhs.line < rhs.line : lhs.number < rhs.number
        }
        var result = PortablePlaylistImportResult()
        for entry in entries {
            guard !entry.value.isEmpty else {
                result.issues.append(.init(line: entry.line, value: entry.value, kind: .malformedEntry))
                continue
            }
            append(entry.value, line: entry.line, relativeTo: baseURL, result: &result)
        }
        return result
    }

    private func append(
        _ value: String,
        line: Int,
        relativeTo baseURL: URL,
        result: inout PortablePlaylistImportResult
    ) {
        if let parsed = URL(string: value), let scheme = parsed.scheme, !scheme.isEmpty {
            if parsed.isFileURL {
                appendLocal(parsed, original: value, line: line, result: &result)
            } else {
                result.issues.append(.init(line: line, value: value, kind: .unsupportedRemoteURL))
            }
            return
        }

        let expanded = (value as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : baseURL.appendingPathComponent(expanded)
        appendLocal(url.standardizedFileURL, original: value, line: line, result: &result)
    }

    private func appendLocal(
        _ url: URL,
        original: String,
        line: Int,
        result: inout PortablePlaylistImportResult
    ) {
        result.localURLs.append(url)
        if !FileManager.default.fileExists(atPath: url.path) {
            result.issues.append(.init(line: line, value: original, kind: .missingLocalFile))
        }
    }

    private func portablePath(for url: URL, relativeTo baseURL: URL?) -> String {
        guard let baseURL,
              let relative = url.standardizedFileURL.relativePath(from: baseURL.standardizedFileURL),
              !relative.hasPrefix("../") else {
            return url.path
        }
        return relative
    }
}

private extension String {
    var removingUTF8BOM: String {
        first == "\u{FEFF}" ? String(dropFirst()) : self
    }

    var linesPreservingEmpty: [Substring] {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
    }
}

private extension URL {
    func relativePath(from base: URL) -> String? {
        let baseComponents = base.pathComponents
        let targetComponents = pathComponents
        var common = 0
        while common < min(baseComponents.count, targetComponents.count),
              baseComponents[common] == targetComponents[common] {
            common += 1
        }
        guard common > 0 else { return nil }
        let parents = Array(repeating: "..", count: baseComponents.count - common)
        let children = targetComponents.dropFirst(common)
        let combined = parents + children
        return combined.isEmpty ? "." : combined.joined(separator: "/")
    }
}
