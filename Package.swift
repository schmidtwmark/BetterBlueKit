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
        // Only expose the library as a product.
        // BBCLI is kept as an internal executable target for development/testing
        // and can be built via `swift build` but won't be compiled when the
        // package is used as a dependency.
        .library(
            name: "BetterBlueKit",
            targets: ["BetterBlueKit"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.61.0")
    ],
    targets: [
        .target(
            name: "BetterBlueKit",
            dependencies: [],
            path: "Sources/BetterBlueKit",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("RELEASE", .when(configuration: .release))
            ],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")],
        ),
        .executableTarget(
            name: "BBCLI",
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
