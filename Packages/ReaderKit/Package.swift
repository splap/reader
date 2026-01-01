// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ReaderKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ReaderCore", targets: ["ReaderCore"]),
        .library(name: "ReaderUI", targets: ["ReaderUI"])
    ],
    targets: [
        .target(
            name: "ReaderCore"
        ),
        .target(
            name: "ReaderUI",
            dependencies: ["ReaderCore"]
        ),
        .testTarget(
            name: "ReaderCoreTests",
            dependencies: ["ReaderCore"]
        ),
        .testTarget(
            name: "ReaderUITests",
            dependencies: ["ReaderUI", "ReaderCore"]
        )
    ]
)
