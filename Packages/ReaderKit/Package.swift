// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ReaderKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ReaderCore", targets: ["ReaderCore"]),
        .library(name: "ReaderUI", targets: ["ReaderUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.9")
    ],
    targets: [
        .target(
            name: "ReaderCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        ),
        .target(
            name: "ReaderUI",
            dependencies: ["ReaderCore"]
        ),
        .testTarget(
            name: "ReaderCoreTests",
            dependencies: [
                "ReaderCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        ),
        .testTarget(
            name: "ReaderUITests",
            dependencies: ["ReaderUI", "ReaderCore"]
        )
    ]
)
