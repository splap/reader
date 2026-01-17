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
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.9"),
        .package(url: "https://github.com/unum-cloud/usearch.git", from: "2.12.0")
    ],
    targets: [
        .target(
            name: "ReaderCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "USearch", package: "usearch")
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
