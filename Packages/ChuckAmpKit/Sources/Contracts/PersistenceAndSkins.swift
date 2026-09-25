import Foundation

public struct WindowRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum PlayerModule: String, Codable, CaseIterable, Sendable {
    case player
    case equalizer
    case playlist
}

public struct ModuleLayout: Codable, Equatable, Sendable {
    public var module: PlayerModule
    public var frame: WindowRect
    public var isVisible: Bool
    public var groupID: UUID?

    public init(module: PlayerModule, frame: WindowRect, isVisible: Bool, groupID: UUID? = nil) {
        self.module = module
        self.frame = frame
        self.isVisible = isVisible
        self.groupID = groupID
    }
}

public struct WindowLayout: Codable, Equatable, Sendable {
    public var scale: Double
    public var isCompact: Bool
    public var modules: [ModuleLayout]

    public init(scale: Double = 1, isCompact: Bool = false, modules: [ModuleLayout] = []) {
        self.scale = scale
        self.isCompact = isCompact
        self.modules = modules
    }
}

public struct SessionState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var queue: [QueueEntry]
    public var tracks: [TrackReference]
    public var currentEntryID: QueueEntryID?
    public var selectedEntryID: QueueEntryID?
    public var isShuffled: Bool
    public var repeatMode: RepeatMode
    public var position: TimeInterval
    public var volume: Double
    public var equalizer: EQSettings
    public var skinID: String
    public var windowLayout: WindowLayout

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        queue: [QueueEntry] = [],
        tracks: [TrackReference] = [],
        currentEntryID: QueueEntryID? = nil,
        selectedEntryID: QueueEntryID? = nil,
        isShuffled: Bool = false,
        repeatMode: RepeatMode = .off,
        position: TimeInterval = 0,
        volume: Double = 1,
        equalizer: EQSettings = EQSettings(),
        skinID: String = "studio-graphite",
        windowLayout: WindowLayout = WindowLayout()
    ) {
        self.schemaVersion = schemaVersion
        self.queue = queue
        self.tracks = tracks
        self.currentEntryID = currentEntryID
        self.selectedEntryID = selectedEntryID
        self.isShuffled = isShuffled
        self.repeatMode = repeatMode
        self.position = position
        self.volume = volume
        self.equalizer = equalizer
        self.skinID = skinID
        self.windowLayout = windowLayout
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, queue, tracks, currentEntryID, selectedEntryID, isShuffled, repeatMode
        case position, volume, equalizer, skinID, windowLayout
    }

    public init(from decoder: any Swift.Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        queue = try values.decode([QueueEntry].self, forKey: .queue)
        tracks = try values.decode([TrackReference].self, forKey: .tracks)
        currentEntryID = try values.decodeIfPresent(QueueEntryID.self, forKey: .currentEntryID)
        selectedEntryID = try values.decodeIfPresent(QueueEntryID.self, forKey: .selectedEntryID)
        isShuffled = try values.decodeIfPresent(Bool.self, forKey: .isShuffled) ?? false
        repeatMode = try values.decodeIfPresent(RepeatMode.self, forKey: .repeatMode) ?? .off
        position = try values.decode(TimeInterval.self, forKey: .position)
        volume = try values.decode(Double.self, forKey: .volume)
        equalizer = try values.decode(EQSettings.self, forKey: .equalizer)
        skinID = try values.decode(String.self, forKey: .skinID)
        windowLayout = try values.decode(WindowLayout.self, forKey: .windowLayout)
    }
}

public protocol SessionStore: Sendable {
    func load() async throws -> SessionState?
    func save(_ state: SessionState) async throws
}

public struct SkinManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var author: String
    public var version: String
    public var license: String?
    public var colors: [String: String]
    public var fonts: [String: String]
    public var assets: [String: String]

    public init(
        schemaVersion: Int = 1,
        id: String,
        name: String,
        author: String,
        version: String,
        license: String? = nil,
        colors: [String: String] = [:],
        fonts: [String: String] = [:],
        assets: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.author = author
        self.version = version
        self.license = license
        self.colors = colors
        self.fonts = fonts
        self.assets = assets
    }
}

public struct ResolvedSkin: Equatable, Sendable {
    public var manifest: SkinManifest
    public var rootURL: URL
    public var resolvedAssets: [String: URL]

    public init(manifest: SkinManifest, rootURL: URL, resolvedAssets: [String: URL]) {
        self.manifest = manifest
        self.rootURL = rootURL
        self.resolvedAssets = resolvedAssets
    }
}
