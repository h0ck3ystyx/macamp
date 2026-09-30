import Foundation

public enum ApplicationSupportMigration {
    /// Copies files from a legacy product support directory without replacing
    /// anything the renamed app has already created. The operation is safe to
    /// repeat after an interrupted migration.
    @discardableResult
    public static func prepare(
        preferredRoot: URL,
        legacyRoot: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try prepare(preferredRoot: preferredRoot, legacyRoots: [legacyRoot], fileManager: fileManager)
    }

    /// Copies missing files from former product directories in priority order.
    /// The most recent legacy name should be listed first.
    @discardableResult
    public static func prepare(
        preferredRoot: URL,
        legacyRoots: [URL],
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(at: preferredRoot, withIntermediateDirectories: true)
        for legacyRoot in legacyRoots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: legacyRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            for source in try fileManager.contentsOfDirectory(
                at: legacyRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                let destination = preferredRoot.appendingPathComponent(source.lastPathComponent)
                guard !fileManager.fileExists(atPath: destination.path) else { continue }
                try fileManager.copyItem(at: source, to: destination)
            }
        }
        return preferredRoot
    }
}
