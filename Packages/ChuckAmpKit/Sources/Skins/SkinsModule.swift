import Foundation
import Contracts

public enum SkinColorKey: String, CaseIterable, Sendable {
    case windowBackground = "color.window.background"
    case displayBackground = "color.display.background"
    case textPrimary = "color.text.primary"
    case textSecondary = "color.text.secondary"
    case accent = "color.accent"
    case border = "color.border"
}

public enum SkinFontKey: String, CaseIterable, Sendable {
    case track = "font.track"
    case technical = "font.technical"
    case controls = "font.controls"
}

public enum SkinAssetKey: String, CaseIterable, Sendable {
    case windowFrame = "asset.window.frame"
    case previous = "asset.transport.previous"
    case play = "asset.transport.play"
    case pause = "asset.transport.pause"
    case stop = "asset.transport.stop"
    case next = "asset.transport.next"
    case sliderTrack = "asset.slider.track"
    case sliderThumb = "asset.slider.thumb"
    case equalizerTrack = "asset.eq.track"
    case equalizerThumb = "asset.eq.thumb"
}

public enum SkinFontValue: String, CaseIterable, Sendable {
    case system
    case systemRounded = "system-rounded"
    case systemMonospaced = "system-monospaced"
}

public enum PrototypeSkin: String, CaseIterable, Sendable {
    case studioGraphite = "StudioGraphite"
    case paper = "Paper"
    case terminal = "Terminal"

    public var skinID: String {
        switch self {
        case .studioGraphite: "studio-graphite"
        case .paper: "paper"
        case .terminal: "terminal"
        }
    }
}

public struct SkinAccentVariation: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var accent: String
    public var displayBackground: String?

    public init(id: String, name: String, accent: String, displayBackground: String? = nil) {
        self.id = id
        self.name = name
        self.accent = accent
        self.displayBackground = displayBackground
    }
}

public extension SkinAccentVariation {
    static let graphiteElectricBlue = SkinAccentVariation(
        id: "electric-blue", name: "Electric Blue", accent: "#55B8FF"
    )
    static let paperPlum = SkinAccentVariation(
        id: "plum", name: "Plum", accent: "#8B3F75"
    )
    static let terminalAmber = SkinAccentVariation(
        id: "amber", name: "Amber", accent: "#FFB000", displayBackground: "#1B1200"
    )
}

public enum SkinValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    case unreadableManifest
    case unsupportedSchemaVersion(Int)
    case invalidIdentity(field: String)
    case unknownKey(section: String, key: String)
    case missingRequiredKey(section: String, key: String)
    case invalidColor(key: String, value: String)
    case invalidFont(key: String, value: String)
    case unsafeAssetPath(key: String, path: String)
    case missingAsset(key: String, path: String)

    public var description: String {
        switch self {
        case .unreadableManifest: "The skin manifest could not be read."
        case let .unsupportedSchemaVersion(version): "Unsupported skin schema version \(version)."
        case let .invalidIdentity(field): "The skin has an invalid \(field)."
        case let .unknownKey(section, key): "Unknown \(section) key: \(key)."
        case let .missingRequiredKey(section, key): "Missing required \(section) key: \(key)."
        case let .invalidColor(key, value): "Invalid color \(value) for \(key)."
        case let .invalidFont(key, value): "Invalid font \(value) for \(key)."
        case let .unsafeAssetPath(key, path): "Unsafe asset path \(path) for \(key)."
        case let .missingAsset(key, path): "Missing asset \(path) for \(key)."
        }
    }
}

public struct SkinResolver: Sendable {
    public static let schemaVersion = 1
    public static let manifestFilename = "manifest.json"

    private static let requiredAssets: Set<SkinAssetKey> = [.windowFrame, .play, .pause]
    public init() {}

    public func resolve(directory: URL) throws -> ResolvedSkin {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let manifestURL = root.appendingPathComponent(Self.manifestFilename, isDirectory: false)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(SkinManifest.self, from: data) else {
            throw SkinValidationError.unreadableManifest
        }
        return try resolve(manifest: manifest, rootURL: root)
    }

    public func resolve(_ skin: PrototypeSkin, under skinsRoot: URL) throws -> ResolvedSkin {
        let resolved = try resolve(directory: skinsRoot.appendingPathComponent(skin.rawValue, isDirectory: true))
        guard resolved.manifest.id == skin.skinID else {
            throw SkinValidationError.invalidIdentity(field: "id")
        }
        return resolved
    }

    public func resolve(variation: SkinAccentVariation, basedOn skin: ResolvedSkin) throws -> ResolvedSkin {
        let validVariationID = variation.id.range(of: #"^[a-z0-9]+(?:[.-][a-z0-9]+)*$"#, options: .regularExpression) != nil
        guard validVariationID, !variation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SkinValidationError.invalidIdentity(field: "variation")
        }
        var manifest = skin.manifest
        manifest.id += "." + variation.id
        manifest.name += " — " + variation.name
        manifest.colors[SkinColorKey.accent.rawValue] = variation.accent
        if let displayBackground = variation.displayBackground {
            manifest.colors[SkinColorKey.displayBackground.rawValue] = displayBackground
        }
        return try resolve(manifest: manifest, rootURL: skin.rootURL)
    }

    /// Suitable for a future archive importer after safe extraction to a private directory.
    public func resolve(manifest: SkinManifest, rootURL: URL) throws -> ResolvedSkin {
        guard manifest.schemaVersion == Self.schemaVersion else {
            throw SkinValidationError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        try validateIdentity(manifest)
        try validateKeys(manifest)

        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        var resolvedAssets: [String: URL] = [:]
        for (key, relativePath) in manifest.assets {
            resolvedAssets[key] = try resolveAsset(key: key, path: relativePath, root: root)
        }
        return ResolvedSkin(manifest: manifest, rootURL: root, resolvedAssets: resolvedAssets)
    }

    private func validateIdentity(_ manifest: SkinManifest) throws {
        let validID = manifest.id.range(of: #"^[a-z0-9]+(?:[.-][a-z0-9]+)*$"#, options: .regularExpression) != nil
        guard validID else { throw SkinValidationError.invalidIdentity(field: "id") }
        for (field, value) in [("name", manifest.name), ("author", manifest.author), ("version", manifest.version)] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SkinValidationError.invalidIdentity(field: field)
            }
        }
    }

    private func validateKeys(_ manifest: SkinManifest) throws {
        try rejectUnknown(keys: manifest.colors.keys, allowed: Set(SkinColorKey.allCases.map(\.rawValue)), section: "color")
        try rejectUnknown(keys: manifest.fonts.keys, allowed: Set(SkinFontKey.allCases.map(\.rawValue)), section: "font")
        try rejectUnknown(keys: manifest.assets.keys, allowed: Set(SkinAssetKey.allCases.map(\.rawValue)), section: "asset")

        for key in SkinColorKey.allCases {
            guard let value = manifest.colors[key.rawValue] else {
                throw SkinValidationError.missingRequiredKey(section: "color", key: key.rawValue)
            }
            guard Self.isHexColor(value) else {
                throw SkinValidationError.invalidColor(key: key.rawValue, value: value)
            }
        }
        for key in SkinFontKey.allCases {
            guard let value = manifest.fonts[key.rawValue] else {
                throw SkinValidationError.missingRequiredKey(section: "font", key: key.rawValue)
            }
            guard SkinFontValue(rawValue: value) != nil else {
                throw SkinValidationError.invalidFont(key: key.rawValue, value: value)
            }
        }
        for key in Self.requiredAssets where manifest.assets[key.rawValue] == nil {
            throw SkinValidationError.missingRequiredKey(section: "asset", key: key.rawValue)
        }
    }

    private func rejectUnknown<S: Sequence>(keys: S, allowed: Set<String>, section: String) throws where S.Element == String {
        if let key = keys.first(where: { !allowed.contains($0) }) {
            throw SkinValidationError.unknownKey(section: section, key: key)
        }
    }

    private func resolveAsset(key: String, path: String, root: URL) throws -> URL {
        let pathComponents = NSString(string: path).pathComponents
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !pathComponents.contains(".."), !pathComponents.contains("."),
              pathComponents.joined(separator: "/") == path else {
            throw SkinValidationError.unsafeAssetPath(key: key, path: path)
        }

        let unresolved = root.appendingPathComponent(path, isDirectory: false).standardizedFileURL
        let resolved = unresolved.resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resolved.path.hasPrefix(rootPrefix) else {
            throw SkinValidationError.unsafeAssetPath(key: key, path: path)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw SkinValidationError.missingAsset(key: key, path: path)
        }
        return resolved
    }

    private static func isHexColor(_ value: String) -> Bool {
        value.range(of: #"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$"#, options: .regularExpression) != nil
    }
}

public extension ResolvedSkin {
    func color(_ key: SkinColorKey) -> String { manifest.colors[key.rawValue]! }
    func font(_ key: SkinFontKey) -> SkinFontValue { SkinFontValue(rawValue: manifest.fonts[key.rawValue]!)! }
    func asset(_ key: SkinAssetKey) -> URL? { resolvedAssets[key.rawValue] }
}

@MainActor
public final class LiveSkinSelection {
    public private(set) var activeSkin: ResolvedSkin
    private var observers: [UUID: (ResolvedSkin) -> Void] = [:]
    private var activePreview: SkinPackagePreview?

    public init(activeSkin: ResolvedSkin) { self.activeSkin = activeSkin }

    public func apply(_ skin: ResolvedSkin) {
        activePreview = nil
        activeSkin = skin
        for observer in observers.values { observer(skin) }
    }

    /// Retains the preview's private extraction directory for as long as its
    /// artwork is active. A later apply releases it.
    public func apply(_ preview: SkinPackagePreview) {
        activePreview = preview
        activeSkin = preview.skin
        for observer in observers.values { observer(preview.skin) }
    }

    public func apply(directory: URL, using resolver: SkinResolver = SkinResolver()) throws {
        let resolved = try resolver.resolve(directory: directory)
        apply(resolved)
    }

    @discardableResult
    public func observe(_ observer: @escaping (ResolvedSkin) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        observer(activeSkin)
        return id
    }

    public func removeObserver(_ id: UUID) { observers[id] = nil }
}

public enum SkinsModule {
    public static let isPrototypeImplemented = true
}
