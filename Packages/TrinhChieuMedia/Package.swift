// swift-tools-version: 6.0
import PackageDescription

let commonSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
]

let coreModel: Target.Dependency = .product(name: "CoreModel", package: "TrinhChieuCore")

let package = Package(
    name: "TrinhChieuMedia",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RenderEngine", targets: ["RenderEngine"]),
        .library(name: "MediaImport", targets: ["MediaImport"]),
        .executable(name: "ProbeApp", targets: ["ProbeApp"]),
    ],
    dependencies: [
        .package(path: "../TrinhChieuCore")
    ],
    targets: [
        .target(
            name: "RenderEngine",
            dependencies: [coreModel],
            resources: [.process("Shaders")],
            swiftSettings: commonSettings
        ),
        .testTarget(
            name: "RenderEngineTests",
            dependencies: ["RenderEngine"],
            exclude: ["Fixtures"],
            swiftSettings: commonSettings
        ),
        .target(name: "MediaImport", dependencies: [coreModel], swiftSettings: commonSettings),
        .testTarget(name: "MediaImportTests", dependencies: ["MediaImport"], swiftSettings: commonSettings),
        // Bản thử Metal (T0.4): `swift run -c release ProbeApp --help`.
        .executableTarget(name: "ProbeApp", dependencies: ["RenderEngine"], swiftSettings: commonSettings),
    ]
)
