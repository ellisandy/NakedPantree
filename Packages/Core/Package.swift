// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "NakedPantreeDomain",
            targets: ["NakedPantreeDomain"]
        ),
        .library(
            name: "NakedPantreePersistence",
            targets: ["NakedPantreePersistence"]
        ),
    ],
    targets: [
        .target(name: "NakedPantreeDomain"),
        .target(
            name: "NakedPantreePersistence",
            dependencies: ["NakedPantreeDomain"]
        ),
        .testTarget(
            name: "NakedPantreeDomainTests",
            dependencies: ["NakedPantreeDomain"]
        ),
        .testTarget(
            name: "NakedPantreePersistenceTests",
            dependencies: ["NakedPantreePersistence"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
