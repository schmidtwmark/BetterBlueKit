// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "BetterBlueKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v11)
    ],
    products: [
        .library(
            name: "BetterBlueKit",
            targets: ["BetterBlueKit"]
        ),
        .executable(
            name: "bbcli",
            targets: ["bbcli"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.61.0")
    ],
    targets: [
        .target(
            name: "BetterBlueKit",
            dependencies: [],
            path: "Sources/BetterBlueKit",
            resources: [
                // Bundles the shared troubleshooting document so the main
                // app and Watch app can both surface it in-UI via
                // `TroubleshootingDocument.markdown`. The file at the
                // repo root is a symlink to the same source so GitHub
                // renders it at its standard location.
                .process("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("RELEASE", .when(configuration: .release))
            ],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")],
        ),
        .executableTarget(
            name: "bbcli",
            dependencies: ["BetterBlueKit"],
            path: "Sources/BBCLI"
        ),
        .testTarget(
            name: "BetterBlueKitTests",
            dependencies: ["BetterBlueKit"]
        )
    ],
    swiftLanguageModes: [.v5, .v6],
)
