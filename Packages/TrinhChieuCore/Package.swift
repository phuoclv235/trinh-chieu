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
    dependencies: [
        // Thư viện ngoài đã duyệt (docs/kien-truc.md mục 6).
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.12.0"),
        // Gói mang đi (LibraryStore), sau này đọc PPTX.
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
    ],
    targets: [
        .target(name: "VietText", swiftSettings: commonSettings),
        .testTarget(name: "VietTextTests", dependencies: ["VietText"], swiftSettings: commonSettings),
        .target(name: "CoreModel", dependencies: ["VietText"], swiftSettings: commonSettings),
        .testTarget(
            name: "CoreModelTests", dependencies: ["CoreModel"], exclude: ["Fixtures"], swiftSettings: commonSettings
        ),
        .target(
            name: "Scripture",
            dependencies: ["CoreModel", "VietText", .product(name: "GRDB", package: "GRDB.swift")],
            resources: [.process("Resources")],
            swiftSettings: commonSettings
        ),
        .testTarget(name: "ScriptureTests", dependencies: ["Scripture", "CoreModel"], swiftSettings: commonSettings),
        .target(
            name: "LibraryIndex",
            dependencies: ["Scripture", "VietText", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: commonSettings
        ),
        .testTarget(name: "LibraryIndexTests", dependencies: ["LibraryIndex"], swiftSettings: commonSettings),
        .target(
            name: "LibraryStore",
            dependencies: [
                "CoreModel", "Scripture", "LibraryIndex", .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [.copy("Resources/default-themes")],
            swiftSettings: commonSettings
        ),
        .testTarget(
            name: "LibraryStoreTests", dependencies: ["LibraryStore", "Scripture", "ZIPFoundation"],
            exclude: ["Fixtures"], swiftSettings: commonSettings
        ),
        .target(
            name: "Importers", dependencies: ["CoreModel", "Scripture", "VietText"], swiftSettings: commonSettings
        ),
        .testTarget(
            name: "ImportersTests", dependencies: ["Importers", "CoreModel", "Scripture", "VietText"],
            resources: [.copy("Fixtures")], swiftSettings: commonSettings
        ),
    ]
)
