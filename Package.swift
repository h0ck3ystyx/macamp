// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MacAmp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacAmp", targets: ["MacAmpApp"]),
        .executable(name: "AudioProbe", targets: ["AudioProbe"]),
        .library(name: "MacAmpContracts", targets: ["Contracts"]),
        .library(name: "MacAmpAudio", targets: ["Audio"]),
        .library(name: "MacAmpLibrary", targets: ["Library"]),
        .library(name: "MacAmpSkins", targets: ["Skins"]),
        .library(name: "MacAmpPlayerUI", targets: ["PlayerUI"]),
        .library(name: "MacAmpMacIntegration", targets: ["MacIntegration"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.19"),
    ],
    targets: [
        .target(name: "Contracts", path: "Packages/MacAmpKit/Sources/Contracts"),
        .target(
            name: "Audio",
            dependencies: [
                "Contracts",
            ],
            path: "Packages/MacAmpKit/Sources/Audio"
        ),
        .target(
            name: "Library",
            dependencies: ["Contracts"],
            path: "Packages/MacAmpKit/Sources/Library"
        ),
        .target(
            name: "Skins",
            dependencies: [
                "Contracts",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Packages/MacAmpKit/Sources/Skins"
        ),
        .target(
            name: "PlayerUI",
            dependencies: ["Contracts", "Skins"],
            path: "Packages/MacAmpKit/Sources/PlayerUI"
        ),
        .target(
            name: "MacIntegration",
            dependencies: ["Contracts", "Audio", "Library"],
            path: "Packages/MacAmpKit/Sources/MacIntegration"
        ),
        .target(
            name: "TestSupport",
            dependencies: ["Contracts"],
            path: "Packages/MacAmpKit/Sources/TestSupport"
        ),
        .executableTarget(
            name: "MacAmpApp",
            dependencies: ["Contracts", "Audio", "Library", "Skins", "PlayerUI", "MacIntegration"],
            path: "MacAmp/App"
        ),
        .executableTarget(
            name: "AudioProbe",
            dependencies: ["Contracts", "Audio"],
            path: "Tools/AudioProbe"
        ),
        .testTarget(
            name: "ContractsTests",
            dependencies: ["Contracts", "TestSupport"],
            path: "Packages/MacAmpKit/Tests/ContractsTests"
        ),
        .testTarget(
            name: "AudioTests",
            dependencies: ["Contracts", "Audio"],
            path: "Packages/MacAmpKit/Tests/AudioTests"
        ),
        .testTarget(
            name: "LibraryTests",
            dependencies: ["Contracts", "Library", "TestSupport"],
            path: "Packages/MacAmpKit/Tests/LibraryTests"
        ),
        .testTarget(
            name: "PlayerUITests",
            dependencies: ["Contracts", "PlayerUI", "Skins"],
            path: "Packages/MacAmpKit/Tests/PlayerUITests"
        ),
        .testTarget(
            name: "SkinsTests",
            dependencies: [
                "Contracts",
                "Skins",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Packages/MacAmpKit/Tests/SkinsTests"
        ),
        .testTarget(
            name: "MacIntegrationTests",
            dependencies: ["Contracts", "Audio", "Library", "MacIntegration", "TestSupport"],
            path: "Packages/MacAmpKit/Tests/MacIntegrationTests"
        ),
    ]
)
