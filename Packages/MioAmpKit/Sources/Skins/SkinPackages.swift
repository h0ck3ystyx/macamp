import Foundation
import ImageIO
import ZIPFoundation
import Contracts

public struct SkinPackageLimits: Equatable, Sendable {
    public var maximumCompressedBytes: UInt64
    public var maximumExpandedBytes: UInt64
    public var maximumFiles: Int
    public var maximumImageDimension: Int
    public var maximumDecodedImageBytes: UInt64

    public init(
        maximumCompressedBytes: UInt64 = 20 * 1024 * 1024,
        maximumExpandedBytes: UInt64 = 80 * 1024 * 1024,
        maximumFiles: Int = 256,
        maximumImageDimension: Int = 4096,
        maximumDecodedImageBytes: UInt64 = 64 * 1024 * 1024
    ) {
        self.maximumCompressedBytes = maximumCompressedBytes
        self.maximumExpandedBytes = maximumExpandedBytes
        self.maximumFiles = maximumFiles
        self.maximumImageDimension = maximumImageDimension
        self.maximumDecodedImageBytes = maximumDecodedImageBytes
    }

    public static let standard = SkinPackageLimits()
}

public enum SkinPackageError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidPackageExtension
    case unreadableArchive
    case compressedSizeExceeded(actual: UInt64, limit: UInt64)
    case expandedSizeExceeded(actual: UInt64, limit: UInt64)
    case fileCountExceeded(actual: Int, limit: Int)
    case unsafeEntryPath(String)
    case duplicateEntry(String)
    case symbolicLink(String)
    case invalidImage(String)
    case imageDimensionExceeded(path: String, width: Int, height: Int, limit: Int)
    case decodedImageBudgetExceeded(actual: UInt64, limit: UInt64)
    case alreadyInstalled(String)
    case notInstalled(String)
    case destinationExists

    public var description: String {
        switch self {
        case .invalidPackageExtension: "A skin package must use the .mioampskin extension (.macampskin and .chuckskin are also accepted for compatibility)."
        case .unreadableArchive: "The skin package is not a readable ZIP archive."
        case let .compressedSizeExceeded(actual, limit): "Compressed package size \(actual) exceeds \(limit) bytes."
        case let .expandedSizeExceeded(actual, limit): "Expanded package size \(actual) exceeds \(limit) bytes."
        case let .fileCountExceeded(actual, limit): "Package entry count \(actual) exceeds \(limit)."
        case let .unsafeEntryPath(path): "Unsafe package path: \(path)."
        case let .duplicateEntry(path): "Duplicate package path: \(path)."
        case let .symbolicLink(path): "Symbolic links are not allowed: \(path)."
        case let .invalidImage(path): "Asset is not a readable image: \(path)."
        case let .imageDimensionExceeded(path, width, height, limit): "Image \(path) is \(width)×\(height), above \(limit) px."
        case let .decodedImageBudgetExceeded(actual, limit): "Decoded images require \(actual) bytes, above \(limit)."
        case let .alreadyInstalled(id): "Skin \(id) is already installed."
        case let .notInstalled(id): "Skin \(id) is not installed."
        case .destinationExists: "The export destination already exists."
        }
    }
}

public final class SkinPackagePreview: @unchecked Sendable {
    public let skin: ResolvedSkin
    private let extractedDirectory: URL

    fileprivate init(skin: ResolvedSkin, extractedDirectory: URL) {
        self.skin = skin
        self.extractedDirectory = extractedDirectory
    }

    deinit { try? FileManager.default.removeItem(at: extractedDirectory) }
}

/// Synchronous file operations intended to be called from a worker task, never
/// from the audio render callback or the main actor.
public struct SkinPackageManager: Sendable {
    public static let packageExtension = "mioampskin"
    public static let legacyPackageExtensions = ["macampskin", "chuckskin"]
    public let installedSkinsURL: URL
    public let limits: SkinPackageLimits

    public init(installedSkinsURL: URL, limits: SkinPackageLimits = .standard) {
        self.installedSkinsURL = installedSkinsURL.standardizedFileURL
        self.limits = limits
    }

    public func preview(packageURL: URL) throws -> SkinPackagePreview {
        let staging = try makeTemporaryDirectory(prefix: "MioAmp-Skin-Preview")
        do {
            let skin = try extractAndResolve(packageURL: packageURL, into: staging)
            return SkinPackagePreview(skin: skin, extractedDirectory: staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    public func install(packageURL: URL) throws -> ResolvedSkin {
        try FileManager.default.createDirectory(at: installedSkinsURL, withIntermediateDirectories: true)
        let staging = installedSkinsURL.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        let skin = try extractAndResolve(packageURL: packageURL, into: staging)
        let destination = installedSkinsURL.appendingPathComponent(skin.manifest.id, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw SkinPackageError.alreadyInstalled(skin.manifest.id)
        }
        try FileManager.default.moveItem(at: staging, to: destination)
        return try SkinResolver().resolve(directory: destination)
    }

    public func save(variation: SkinAccentVariation, basedOn skin: ResolvedSkin) throws -> ResolvedSkin {
        let varied = try SkinResolver().resolve(variation: variation, basedOn: skin)
        try FileManager.default.createDirectory(at: installedSkinsURL, withIntermediateDirectories: true)
        let destination = installedSkinsURL.appendingPathComponent(varied.manifest.id, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw SkinPackageError.alreadyInstalled(varied.manifest.id)
        }
        let staging = installedSkinsURL.appendingPathComponent(".variation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: skin.rootURL, to: staging)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(varied.manifest).write(
            to: staging.appendingPathComponent(SkinResolver.manifestFilename), options: .atomic
        )
        let resolved = try SkinResolver().resolve(directory: staging)
        try validateImages(in: resolved)
        try FileManager.default.moveItem(at: staging, to: destination)
        return try SkinResolver().resolve(directory: destination)
    }

    public func installedSkin(id: String) throws -> ResolvedSkin {
        guard Self.isValidIdentifier(id) else { throw SkinPackageError.notInstalled(id) }
        let directory = installedSkinsURL.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw SkinPackageError.notInstalled(id) }
        return try SkinResolver().resolve(directory: directory)
    }

    public func remove(id: String) throws {
        guard Self.isValidIdentifier(id) else { throw SkinPackageError.notInstalled(id) }
        let directory = installedSkinsURL.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw SkinPackageError.notInstalled(id) }
        try FileManager.default.removeItem(at: directory)
    }

    public func export(id: String, to packageURL: URL) throws {
        let skin = try installedSkin(id: id)
        try export(directory: skin.rootURL, to: packageURL)
    }

    /// Exports a validated creator directory. This is also the creator-starter
    /// path and deliberately uses the same schema as installed and bundled skins.
    public func export(directory: URL, to packageURL: URL) throws {
        guard Self.isSupportedPackage(packageURL) else {
            throw SkinPackageError.invalidPackageExtension
        }
        guard !FileManager.default.fileExists(atPath: packageURL.path) else {
            throw SkinPackageError.destinationExists
        }
        let resolved = try SkinResolver().resolve(directory: directory)
        try validateImages(in: resolved)
        let entries = try exportEntries(in: resolved.rootURL)

        let temporaryArchive = packageURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).\(Self.packageExtension)")
        defer { try? FileManager.default.removeItem(at: temporaryArchive) }
        let archive: Archive
        do { archive = try Archive(url: temporaryArchive, accessMode: .create) }
        catch { throw SkinPackageError.unreadableArchive }
        for entry in entries {
            try archive.addEntry(with: entry, relativeTo: resolved.rootURL, compressionMethod: .deflate)
        }
        let compressedBytes = try fileSize(at: temporaryArchive)
        guard compressedBytes <= limits.maximumCompressedBytes else {
            throw SkinPackageError.compressedSizeExceeded(actual: compressedBytes, limit: limits.maximumCompressedBytes)
        }
        try FileManager.default.moveItem(at: temporaryArchive, to: packageURL)
    }

    private func extractAndResolve(packageURL: URL, into staging: URL) throws -> ResolvedSkin {
        guard Self.isSupportedPackage(packageURL) else {
            throw SkinPackageError.invalidPackageExtension
        }
        let archiveBytes = try fileSize(at: packageURL)
        guard archiveBytes <= limits.maximumCompressedBytes else {
            throw SkinPackageError.compressedSizeExceeded(actual: archiveBytes, limit: limits.maximumCompressedBytes)
        }

        let archive: Archive
        do { archive = try Archive(url: packageURL, accessMode: .read) }
        catch { throw SkinPackageError.unreadableArchive }
        let entries = Array(archive)
        guard entries.count <= limits.maximumFiles else {
            throw SkinPackageError.fileCountExceeded(actual: entries.count, limit: limits.maximumFiles)
        }

        var names = Set<String>()
        var expandedBytes: UInt64 = 0
        var declaredCompressedBytes: UInt64 = 0
        for entry in entries {
            let path = try validatedArchivePath(entry.path)
            let comparisonPath = path.precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(comparisonPath).inserted else { throw SkinPackageError.duplicateEntry(path) }
            guard entry.type != .symlink else { throw SkinPackageError.symbolicLink(path) }
            expandedBytes = try adding(entry.uncompressedSize, to: expandedBytes, limit: limits.maximumExpandedBytes) {
                SkinPackageError.expandedSizeExceeded(actual: $0, limit: limits.maximumExpandedBytes)
            }
            declaredCompressedBytes = try adding(entry.compressedSize, to: declaredCompressedBytes, limit: limits.maximumCompressedBytes) {
                SkinPackageError.compressedSizeExceeded(actual: $0, limit: limits.maximumCompressedBytes)
            }
        }

        for entry in entries {
            let path = try validatedArchivePath(entry.path)
            let destination = staging.appendingPathComponent(path, isDirectory: entry.type == .directory)
            do { _ = try archive.extract(entry, to: destination, skipCRC32: false, allowUncontainedSymlinks: false) }
            catch { throw SkinPackageError.unreadableArchive }
        }
        let skin = try SkinResolver().resolve(directory: staging)
        try validateImages(in: skin)
        return skin
    }

    public static func isSupportedPackage(_ url: URL) -> Bool {
        ([packageExtension] + legacyPackageExtensions).contains(url.pathExtension.lowercased())
    }

    private func exportEntries(in root: URL) throws -> [String] {
        let subpaths = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        var entries: [String] = []
        var expandedBytes: UInt64 = 0
        for relative in subpaths where !relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
            let url = root.appendingPathComponent(relative)
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            _ = try validatedArchivePath(relative + (values.isDirectory == true ? "/" : ""))
            if values.isSymbolicLink == true { throw SkinPackageError.symbolicLink(relative) }
            guard values.isDirectory == true || values.isRegularFile == true else {
                throw SkinPackageError.unsafeEntryPath(relative)
            }
            entries.append(relative)
            if values.isRegularFile == true {
                expandedBytes = try adding(UInt64(values.fileSize ?? 0), to: expandedBytes, limit: limits.maximumExpandedBytes) {
                    SkinPackageError.expandedSizeExceeded(actual: $0, limit: limits.maximumExpandedBytes)
                }
            }
        }
        guard entries.count <= limits.maximumFiles else {
            throw SkinPackageError.fileCountExceeded(actual: entries.count, limit: limits.maximumFiles)
        }
        return entries.sorted()
    }

    private func validateImages(in skin: ResolvedSkin) throws {
        var decodedBytes: UInt64 = 0
        for (key, url) in skin.resolvedAssets.sorted(by: { $0.key < $1.key }) {
            guard let (width, height) = imageDimensions(at: url) else {
                throw SkinPackageError.invalidImage(key)
            }
            guard width > 0, height > 0 else { throw SkinPackageError.invalidImage(key) }
            guard width <= limits.maximumImageDimension, height <= limits.maximumImageDimension else {
                throw SkinPackageError.imageDimensionExceeded(
                    path: key, width: width, height: height, limit: limits.maximumImageDimension
                )
            }
            let pixels = UInt64(width) * UInt64(height)
            decodedBytes = try adding(pixels * 4, to: decodedBytes, limit: limits.maximumDecodedImageBytes) {
                SkinPackageError.decodedImageBudgetExceeded(actual: $0, limit: limits.maximumDecodedImageBytes)
            }
        }
    }

    private func imageDimensions(at url: URL) -> (Int, Int)? {
        if url.pathExtension.lowercased() == "svg" {
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  data.count <= 512 * 1024,
                  let text = String(data: data, encoding: .utf8) else { return nil }
            let lower = text.lowercased()
            let withoutLocalPaintReferences = lower.replacingOccurrences(
                of: #"url\(\s*#[-a-z0-9_]+\s*\)"#,
                with: "",
                options: .regularExpression
            )
            guard lower.contains("<svg"),
                  !lower.contains("<script"), !lower.contains("<!doctype"), !lower.contains("<!entity"),
                  !lower.contains("href="), !withoutLocalPaintReferences.contains("url(") else { return nil }
            return svgDimension("width", in: text).flatMap { width in
                svgDimension("height", in: text).map { (width, $0) }
            }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
        return (width, height)
    }

    private func svgDimension(_ attribute: String, in text: String) -> Int? {
        let pattern = #"\b"# + attribute + #"\s*=\s*[\"']([0-9]+(?:\.[0-9]+)?)(?:px)?[\"']"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]), value.isFinite, value > 0, value <= Double(Int.max) else { return nil }
        return Int(value.rounded(.up))
    }

    private func validatedArchivePath(_ path: String) throws -> String {
        let isDirectory = path.hasSuffix("/")
        let trimmed = isDirectory ? String(path.dropLast()) : path
        let components = NSString(string: trimmed).pathComponents
        let hasOnlySafeScalars = trimmed.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7f }
        guard !trimmed.isEmpty, trimmed.utf8.count <= 1024, hasOnlySafeScalars,
              !trimmed.hasPrefix("/"), !trimmed.contains("\\"), !trimmed.contains(":"),
              !components.contains("."), !components.contains(".."),
              components.joined(separator: "/") == trimmed,
              Array(trimmed.precomposedStringWithCanonicalMapping.utf8) == Array(trimmed.utf8) else {
            throw SkinPackageError.unsafeEntryPath(path)
        }
        return trimmed
    }

    private func adding(
        _ value: UInt64,
        to total: UInt64,
        limit: UInt64,
        error: (UInt64) -> SkinPackageError
    ) throws -> UInt64 {
        let (newTotal, overflow) = total.addingReportingOverflow(value)
        guard !overflow, newTotal <= limit else { throw error(overflow ? UInt64.max : newTotal) }
        return newTotal
    }

    private func fileSize(at url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size >= 0 else { throw SkinPackageError.unreadableArchive }
        return UInt64(size)
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private static func isValidIdentifier(_ id: String) -> Bool {
        id.range(of: #"^[a-z0-9]+(?:[.-][a-z0-9]+)*$"#, options: .regularExpression) != nil
    }
}
