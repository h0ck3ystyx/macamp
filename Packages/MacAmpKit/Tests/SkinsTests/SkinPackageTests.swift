import Foundation
import Skins
import Testing
import ZIPFoundation

private var packageRepositoryRoot: URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

private func packageTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func copyCreatorExample(into parent: URL) throws -> URL {
    let destination = parent.appendingPathComponent("Creator", isDirectory: true)
    try FileManager.default.copyItem(
        at: packageRepositoryRoot.appendingPathComponent("Skins/CreatorExample", isDirectory: true),
        to: destination
    )
    return destination
}

private func rawArchive(from directory: URL, to destination: URL) throws {
    let archive = try Archive(url: destination, accessMode: .create)
    for entry in try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted() {
        try archive.addEntry(with: entry, relativeTo: directory, compressionMethod: .deflate)
    }
}

private func validPackage(in root: URL) throws -> URL {
    let packageURL = root.appendingPathComponent("creator.macampskin")
    let creator = try copyCreatorExample(into: root)
    try SkinPackageManager(installedSkinsURL: root.appendingPathComponent("Installed"))
        .export(directory: creator, to: packageURL)
    return packageURL
}

@Test func terminalAndAccentVariationsUsePublicSchema() throws {
    let skins = packageRepositoryRoot.appendingPathComponent("Skins", isDirectory: true)
    let resolver = SkinResolver()
    let terminal = try resolver.resolve(.terminal, under: skins)
    let amber = try resolver.resolve(variation: .terminalAmber, basedOn: terminal)
    #expect(terminal.manifest.id == "terminal")
    #expect(amber.manifest.id == "terminal.amber")
    #expect(amber.color(.accent) == "#FFB000")
    #expect(amber.asset(.play) == terminal.asset(.play))
}

@Test func savedAccentVariationIsIndependentlyExportable() throws {
    let root = try packageTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let resolver = SkinResolver()
    let graphite = try resolver.resolve(
        .studioGraphite, under: packageRepositoryRoot.appendingPathComponent("Skins", isDirectory: true)
    )
    let manager = SkinPackageManager(installedSkinsURL: root.appendingPathComponent("Installed"))
    let saved = try manager.save(variation: .graphiteElectricBlue, basedOn: graphite)
    #expect(saved.manifest.id == "studio-graphite.electric-blue")
    #expect(saved.color(.accent) == "#55B8FF")
    let packageURL = root.appendingPathComponent("variation.macampskin")
    try manager.export(id: saved.manifest.id, to: packageURL)
    #expect(try manager.preview(packageURL: packageURL).skin.manifest == saved.manifest)
}

@Test func creatorStarterPreviewInstallExportRemoveRoundTrip() throws {
    let root = try packageTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let installed = root.appendingPathComponent("Installed", isDirectory: true)
    let manager = SkinPackageManager(installedSkinsURL: installed)
    let sourcePackage = try validPackage(in: root)

    let preview = try manager.preview(packageURL: sourcePackage)
    #expect(preview.skin.manifest.id == "your-name.example")
    let installedSkin = try manager.install(packageURL: sourcePackage)
    #expect(installedSkin.manifest.id == preview.skin.manifest.id)

    let exported = root.appendingPathComponent("exported.macampskin")
    try manager.export(id: installedSkin.manifest.id, to: exported)
    let exportedPreview = try manager.preview(packageURL: exported)
    #expect(exportedPreview.skin.manifest == installedSkin.manifest)
    #expect(exportedPreview.skin.resolvedAssets.keys == installedSkin.resolvedAssets.keys)

    try manager.remove(id: installedSkin.manifest.id)
    #expect(throws: SkinPackageError.notInstalled(installedSkin.manifest.id)) {
        try manager.installedSkin(id: installedSkin.manifest.id)
    }
}

@Test func legacyChuckskinPackagesRemainImportableAfterRename() throws {
    let root = try packageTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let canonical = try validPackage(in: root)
    let legacy = root.appendingPathComponent("legacy.chuckskin")
    try FileManager.default.copyItem(at: canonical, to: legacy)
    let manager = SkinPackageManager(installedSkinsURL: root.appendingPathComponent("Installed"))
    #expect(try manager.preview(packageURL: legacy).skin.manifest.id == "your-name.example")
}

@Test func rejectsTraversalEntryBeforeExtraction() throws {
    let root = try packageTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let packageURL = try validPackage(in: root)
    let payload = root.appendingPathComponent("payload")
    try Data("bad".utf8).write(to: payload)
    let archive = try Archive(url: packageURL, accessMode: .update)
    try archive.addEntry(with: "../escape", fileURL: payload)
    let manager = SkinPackageManager(installedSkinsURL: root.appendingPathComponent("Installed"))
    #expect(throws: SkinPackageError.unsafeEntryPath("../escape")) {
        _ = try manager.preview(packageURL: packageURL)
    }
    #expect(!FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escape").path))
}

@Test func rejectsNonCanonicalUnicodeEntry() throws {
    let root = try packageTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let packageURL = try validPackage(in: root)
    let payload = root.appendingPathComponent("payload")
    try Data("bad".utf8).write(to: payload)
    let nonCanonical = "art/e\u{301}.svg"
    let archive = try Archive(url: packageURL, accessMode: .update)
    try archive.addEntry(with: nonCanonical, fileURL: payload)
    let manager = SkinPackageManager(installedSkinsURL: root.appendingPathComponent("Installed"))
    #expect(throws: SkinPackageError.unsafeEntryPath(nonCanonical)) {
        _ = try manager.preview(packageURL: packageURL)
    }
}

@Test func rejectsWindowsDriveEntry() throws {
    let root = try packageTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let packageURL = try validPackage(in: root)
    let payload = root.appendingPathComponent("payload")
    try Data("bad".utf8).write(to: payload)
    let archive = try Archive(url: packageURL, accessMode: .update)
    try archive.addEntry(with: "C:/escape", fileURL: payload)
    let manager = SkinPackageManager(installedSkinsURL: root.appendingPathComponent("Installed"))
    #expect(throws: SkinPackageError.unsafeEntryPath("C:/escape")) {
        _ = try manager.preview(packageURL: packageURL)
    }
}

@Test func rejectsDuplicateEntriesCaseInsensitively() throws {
    let root = try packageTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let packageURL = try validPackage(in: root)
    let payload = root.appendingPathComponent("payload")
    try Data("bad".utf8).write(to: payload)
    let archive = try Archive(url: packageURL, accessMode: .update)
    try archive.addEntry(with: "MANIFEST.JSON", fileURL: payload)
    let manager = SkinPackageManager(installedSkinsURL: root.appendingPathComponent("Installed"))
    #expect(throws: SkinPackageError.duplicateEntry("MANIFEST.JSON")) {
        _ = try manager.preview(packageURL: packageURL)
    }
}

@Test func rejectsSymbolicLinkEntry() throws {
    let root = try packageTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let packageURL = try validPackage(in: root)
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../outside")
    let archive = try Archive(url: packageURL, accessMode: .update)
    try archive.addEntry(with: "art/link", fileURL: link)
    let manager = SkinPackageManager(installedSkinsURL: root.appendingPathComponent("Installed"))
    #expect(throws: SkinPackageError.symbolicLink("art/link")) {
        _ = try manager.preview(packageURL: packageURL)
    }
}

@Test func enforcesArchiveCountAndSizeBudgets() throws {
    let root = try packageTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let packageURL = try validPackage(in: root)

    let countManager = SkinPackageManager(
        installedSkinsURL: root.appendingPathComponent("Count"),
        limits: SkinPackageLimits(maximumCompressedBytes: 20_000_000, maximumExpandedBytes: 80_000_000, maximumFiles: 2)
    )
    #expect(throws: SkinPackageError.self) { _ = try countManager.preview(packageURL: packageURL) }

    let compressedManager = SkinPackageManager(
        installedSkinsURL: root.appendingPathComponent("Compressed"),
        limits: SkinPackageLimits(maximumCompressedBytes: 1)
    )
    #expect(throws: SkinPackageError.self) { _ = try compressedManager.preview(packageURL: packageURL) }

    let expandedManager = SkinPackageManager(
        installedSkinsURL: root.appendingPathComponent("Expanded"),
        limits: SkinPackageLimits(maximumExpandedBytes: 10)
    )
    #expect(throws: SkinPackageError.self) { _ = try expandedManager.preview(packageURL: packageURL) }
}

@Test func rejectsCorruptAndOversizedArtwork() throws {
    let root = try packageTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let corrupt = try copyCreatorExample(into: root)
    try Data("not an image".utf8).write(to: corrupt.appendingPathComponent("art/play.svg"))
    let corruptPackage = root.appendingPathComponent("corrupt.macampskin")
    try rawArchive(from: corrupt, to: corruptPackage)
    let manager = SkinPackageManager(installedSkinsURL: root.appendingPathComponent("Installed"))
    #expect(throws: SkinPackageError.invalidImage(SkinAssetKey.play.rawValue)) {
        _ = try manager.preview(packageURL: corruptPackage)
    }

    let oversizedRoot = try packageTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: oversizedRoot) }
    let oversized = try copyCreatorExample(into: oversizedRoot)
    let hugeSVG = #"<svg xmlns="http://www.w3.org/2000/svg" width="4097" height="1"/>"#
    try Data(hugeSVG.utf8).write(to: oversized.appendingPathComponent("art/frame.svg"))
    let oversizedPackage = oversizedRoot.appendingPathComponent("oversized.macampskin")
    try rawArchive(from: oversized, to: oversizedPackage)
    #expect(throws: SkinPackageError.imageDimensionExceeded(
        path: SkinAssetKey.windowFrame.rawValue, width: 4097, height: 1, limit: 4096
    )) {
        _ = try manager.preview(packageURL: oversizedPackage)
    }
}

@Test func enforcesAggregateDecodedImageBudget() throws {
    let root = try packageTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let packageURL = try validPackage(in: root)
    let manager = SkinPackageManager(
        installedSkinsURL: root.appendingPathComponent("Installed"),
        limits: SkinPackageLimits(maximumDecodedImageBytes: 32)
    )
    #expect(throws: SkinPackageError.self) { _ = try manager.preview(packageURL: packageURL) }
}
