// swift-tools-version: 6.0
import PackageDescription

let commonSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "TrinhChieuCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VietText", targets: ["VietText"]),
        .library(name: "CoreModel", targets: ["CoreModel"]),
        .library(name: "Scripture", targets: ["Scripture"]),
        .library(name: "LibraryIndex", targets: ["LibraryIndex"]),
        .library(name: "LibraryStore", targets: ["LibraryStore"]),
        .library(name: "Importers", targets: ["Importers"]),
    ],
    targets: [
        .target(name: "VietText", swiftSettings: commonSettings),
        .testTarget(name: "VietTextTests", dependencies: ["VietText"], swiftSettings: commonSettings),
        .target(name: "CoreModel", dependencies: ["VietText"], swiftSettings: commonSettings),
        .testTarget(
            name: "CoreModelTests", dependencies: ["CoreModel"], exclude: ["Fixtures"], swiftSettings: commonSettings
        ),
        .target(name: "Scripture", dependencies: ["CoreModel"], swiftSettings: commonSettings),
        .testTarget(name: "ScriptureTests", dependencies: ["Scripture"], swiftSettings: commonSettings),
        .target(name: "LibraryIndex", dependencies: ["Scripture"], swiftSettings: commonSettings),
        .testTarget(name: "LibraryIndexTests", dependencies: ["LibraryIndex"], swiftSettings: commonSettings),
        .target(name: "LibraryStore", dependencies: ["LibraryIndex"], swiftSettings: commonSettings),
        .testTarget(name: "LibraryStoreTests", dependencies: ["LibraryStore"], swiftSettings: commonSettings),
        .target(name: "Importers", dependencies: ["Scripture"], swiftSettings: commonSettings),
        .testTarget(name: "ImportersTests", dependencies: ["Importers"], swiftSettings: commonSettings),
    ]
)
