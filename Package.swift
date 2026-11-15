// swift-tools-version:6.0
import PackageDescription

var products: [Product] = [
    .library(name: "SkyReaderCore", targets: ["SkyReaderCore"]),
    .executable(name: "skyreader-cli", targets: ["skyreader-cli"]),
]

var targets: [Target] = [
    // Plattformunabhängige Analyse-Engine (Plate Solving, Kataloge, Mond, Kometen, Texte)
    .target(name: "SkyReaderCore", path: "Sources/SkyReaderCore"),
    // Kommandozeilenwerkzeug zum Testen der Engine (auch unter Linux)
    .executableTarget(name: "skyreader-cli", dependencies: ["SkyReaderCore"], path: "Sources/skyreader-cli"),
    .testTarget(name: "SkyReaderCoreTests", dependencies: ["SkyReaderCore"], path: "Tests/SkyReaderCoreTests"),
]

#if os(macOS)
// Die eigentliche macOS-App (SwiftUI). Wird per Scripts/build_app.sh zu SkyReader.app gebündelt.
products.append(.executable(name: "SkyReader", targets: ["SkyReader"]))
targets.append(.executableTarget(name: "SkyReader", dependencies: ["SkyReaderCore"], path: "Sources/SkyReader"))
#endif

let package = Package(
    name: "SkyReader",
    platforms: [.macOS(.v15)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v5]
)
