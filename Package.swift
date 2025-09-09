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
            targets: ["BetterBlueKit"],
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
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("RELEASE", .when(configuration: .release))
            ],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")],
        )
    ],
    swiftLanguageModes: [.v5, .v6],
)
