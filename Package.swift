// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ChuckAmp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ChuckAmp", targets: ["ChuckAmpApp"]),
        .executable(name: "AudioProbe", targets: ["AudioProbe"]),
        .library(name: "ChuckAmpContracts", targets: ["Contracts"]),
        .library(name: "ChuckAmpAudio", targets: ["Audio"]),
        .library(name: "ChuckAmpLibrary", targets: ["Library"]),
        .library(name: "ChuckAmpSkins", targets: ["Skins"]),
        .library(name: "ChuckAmpPlayerUI", targets: ["PlayerUI"]),
        .library(name: "ChuckAmpMacIntegration", targets: ["MacIntegration"]),
    ],
    targets: [
        .target(name: "Contracts", path: "Packages/ChuckAmpKit/Sources/Contracts"),
        .target(
            name: "Audio",
            dependencies: ["Contracts"],
            path: "Packages/ChuckAmpKit/Sources/Audio"
        ),
        .target(
            name: "Library",
            dependencies: ["Contracts"],
            path: "Packages/ChuckAmpKit/Sources/Library"
        ),
        .target(
            name: "Skins",
            dependencies: ["Contracts"],
            path: "Packages/ChuckAmpKit/Sources/Skins"
        ),
        .target(
            name: "PlayerUI",
            dependencies: ["Contracts", "Skins"],
            path: "Packages/ChuckAmpKit/Sources/PlayerUI"
        ),
        .target(
            name: "MacIntegration",
            dependencies: ["Contracts", "Audio", "Library"],
            path: "Packages/ChuckAmpKit/Sources/MacIntegration"
        ),
        .target(
            name: "TestSupport",
            dependencies: ["Contracts"],
            path: "Packages/ChuckAmpKit/Sources/TestSupport"
        ),
        .executableTarget(
            name: "ChuckAmpApp",
            dependencies: ["Contracts", "Audio", "Library", "Skins", "PlayerUI", "MacIntegration"],
            path: "ChuckAmp/App"
        ),
        .executableTarget(
            name: "AudioProbe",
            dependencies: ["Contracts", "Audio"],
            path: "Tools/AudioProbe"
        ),
        .testTarget(
            name: "ContractsTests",
            dependencies: ["Contracts", "TestSupport"],
            path: "Packages/ChuckAmpKit/Tests/ContractsTests"
        ),
        .testTarget(
            name: "AudioTests",
            dependencies: ["Contracts", "Audio"],
            path: "Packages/ChuckAmpKit/Tests/AudioTests"
        ),
        .testTarget(
            name: "LibraryTests",
            dependencies: ["Contracts", "Library", "TestSupport"],
            path: "Packages/ChuckAmpKit/Tests/LibraryTests"
        ),
        .testTarget(
            name: "PlayerUITests",
            dependencies: ["Contracts", "PlayerUI", "Skins"],
            path: "Packages/ChuckAmpKit/Tests/PlayerUITests"
        ),
        .testTarget(
            name: "SkinsTests",
            dependencies: ["Contracts", "Skins"],
            path: "Packages/ChuckAmpKit/Tests/SkinsTests"
        ),
        .testTarget(
            name: "MacIntegrationTests",
            dependencies: ["Contracts", "Audio", "Library", "MacIntegration", "TestSupport"],
            path: "Packages/ChuckAmpKit/Tests/MacIntegrationTests"
        ),
    ]
)
