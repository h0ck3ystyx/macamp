import Foundation
import Contracts
import Skins
import Testing

private let validColors = Dictionary(uniqueKeysWithValues: SkinColorKey.allCases.map { ($0.rawValue, "#112233") })
private let validFonts = Dictionary(uniqueKeysWithValues: SkinFontKey.allCases.map { ($0.rawValue, SkinFontValue.system.rawValue) })

private func fixtureManifest(schemaVersion: Int = 1, assets: [String: String]? = nil) -> SkinManifest {
    SkinManifest(
        schemaVersion: schemaVersion,
        id: "test-skin",
        name: "Test Skin",
        author: "MioAmp Tests",
        version: "1.0.0",
        colors: validColors,
        fonts: validFonts,
        assets: assets ?? [
            SkinAssetKey.windowFrame.rawValue: "frame.svg",
            SkinAssetKey.play.rawValue: "play.svg",
            SkinAssetKey.pause.rawValue: "pause.svg",
        ]
    )
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func addRequiredAssets(to directory: URL) throws {
    for filename in ["frame.svg", "play.svg", "pause.svg"] {
        try Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8).write(to: directory.appendingPathComponent(filename))
    }
}

@Test func rejectsVersionMismatch() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try addRequiredAssets(to: root)
    #expect(throws: SkinValidationError.unsupportedSchemaVersion(2)) {
        try SkinResolver().resolve(manifest: fixtureManifest(schemaVersion: 2), rootURL: root)
    }
}

@Test func rejectsMalformedManifestJSON() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("{ \"schemaVersion\": 1, \"id\":".utf8)
        .write(to: root.appendingPathComponent(SkinResolver.manifestFilename))
    #expect(throws: SkinValidationError.unreadableManifest) {
        try SkinResolver().resolve(directory: root)
    }
}

@Test func rejectsMissingRequiredColor() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try addRequiredAssets(to: root)
    var manifest = fixtureManifest()
    manifest.colors[SkinColorKey.accent.rawValue] = nil
    #expect(throws: SkinValidationError.missingRequiredKey(section: "color", key: SkinColorKey.accent.rawValue)) {
        try SkinResolver().resolve(manifest: manifest, rootURL: root)
    }
}

@Test func rejectsMissingRequiredAssetRole() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try addRequiredAssets(to: root)
    var manifest = fixtureManifest()
    manifest.assets[SkinAssetKey.play.rawValue] = nil
    #expect(throws: SkinValidationError.missingRequiredKey(section: "asset", key: SkinAssetKey.play.rawValue)) {
        try SkinResolver().resolve(manifest: manifest, rootURL: root)
    }
}

@Test func rejectsMissingAssetFile() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try addRequiredAssets(to: root)
    var manifest = fixtureManifest()
    manifest.assets[SkinAssetKey.play.rawValue] = "gone.svg"
    #expect(throws: SkinValidationError.missingAsset(key: SkinAssetKey.play.rawValue, path: "gone.svg")) {
        try SkinResolver().resolve(manifest: manifest, rootURL: root)
    }
}

@Test(arguments: ["../outside.svg", "/tmp/outside.svg", "art/../../outside.svg", "art\\outside.svg"])
func rejectsPathTraversal(path: String) throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try addRequiredAssets(to: root)
    var manifest = fixtureManifest()
    manifest.assets[SkinAssetKey.play.rawValue] = path
    #expect(throws: SkinValidationError.unsafeAssetPath(key: SkinAssetKey.play.rawValue, path: path)) {
        try SkinResolver().resolve(manifest: manifest, rootURL: root)
    }
}

@Test func rejectsSymlinkEscapingRoot() throws {
    let root = try temporaryDirectory()
    let outside = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
    try addRequiredAssets(to: root)
    let outsideAsset = outside.appendingPathComponent("outside.svg")
    try Data("outside".utf8).write(to: outsideAsset)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.svg"), withDestinationURL: outsideAsset)
    var manifest = fixtureManifest()
    manifest.assets[SkinAssetKey.play.rawValue] = "escape.svg"
    #expect(throws: SkinValidationError.unsafeAssetPath(key: SkinAssetKey.play.rawValue, path: "escape.svg")) {
        try SkinResolver().resolve(manifest: manifest, rootURL: root)
    }
}

private var repositoryRoot: URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

@Test func resolvesBundledGraphiteAndPaperThroughSameSchema() throws {
    let skinsRoot = repositoryRoot.appendingPathComponent("Skins", isDirectory: true)
    let resolver = SkinResolver()
    let graphite = try resolver.resolve(directory: skinsRoot.appendingPathComponent("StudioGraphite", isDirectory: true))
    let paper = try resolver.resolve(directory: skinsRoot.appendingPathComponent("Paper", isDirectory: true))

    #expect(graphite.manifest.id == "studio-graphite")
    #expect(paper.manifest.id == "paper")
    #expect(graphite.manifest.colors.keys.sorted() == paper.manifest.colors.keys.sorted())
    #expect(graphite.manifest.assets.keys.sorted() == paper.manifest.assets.keys.sorted())
    #expect(graphite.asset(.windowFrame) != paper.asset(.windowFrame))
    #expect(graphite.color(.accent) != paper.color(.accent))
}

@Test func bundledSkinTextAndAccentMeetNormalTextContrast() throws {
    let skinsRoot = repositoryRoot.appendingPathComponent("Skins", isDirectory: true)
    for directory in ["StudioGraphite", "Paper", "Terminal"] {
        let skin = try SkinResolver().resolve(directory: skinsRoot.appendingPathComponent(directory, isDirectory: true))
        let backgrounds = [skin.color(.windowBackground), skin.color(.displayBackground)]
        for foreground in [skin.color(.textPrimary), skin.color(.textSecondary), skin.color(.accent)] {
            for background in backgrounds {
                #expect(contrastRatio(foreground, background) >= 4.5, "\(skin.manifest.name) uses \(foreground) on \(background)")
            }
        }
    }
}

private func contrastRatio(_ first: String, _ second: String) -> Double {
    let lighter = max(relativeLuminance(first), relativeLuminance(second))
    let darker = min(relativeLuminance(first), relativeLuminance(second))
    return (lighter + 0.05) / (darker + 0.05)
}

private func relativeLuminance(_ hex: String) -> Double {
    let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let raw = UInt64(value, radix: 16) ?? 0
    let channels = [Double((raw >> 16) & 0xff), Double((raw >> 8) & 0xff), Double(raw & 0xff)].map { channel in
        let normalized = channel / 255
        return normalized <= 0.04045 ? normalized / 12.92 : pow((normalized + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
}

@MainActor
@Test func liveSelectionPublishesFullyResolvedSkins() throws {
    let resolver = SkinResolver()
    let graphite = try resolver.resolve(directory: repositoryRoot.appendingPathComponent("Skins/StudioGraphite"))
    let paper = try resolver.resolve(directory: repositoryRoot.appendingPathComponent("Skins/Paper"))
    let selection = LiveSkinSelection(activeSkin: graphite)
    var seen: [String] = []
    selection.observe { seen.append($0.manifest.id) }
    selection.apply(paper)
    #expect(seen == ["studio-graphite", "paper"])
    #expect(selection.activeSkin.manifest.id == "paper")
}

@MainActor
@Test func failedLiveResolutionRetainsActiveSkin() throws {
    let resolver = SkinResolver()
    let graphite = try resolver.resolve(.studioGraphite, under: repositoryRoot.appendingPathComponent("Skins"))
    let selection = LiveSkinSelection(activeSkin: graphite)
    let invalidDirectory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: invalidDirectory) }

    #expect(throws: SkinValidationError.unreadableManifest) {
        try selection.apply(directory: invalidDirectory, using: resolver)
    }
    #expect(selection.activeSkin.manifest.id == "studio-graphite")
}
