// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GitCore", targets: ["GitCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/ibrahimcetin/libgit2.git", exact: "1.9.2")
    ],
    targets: [
        .target(
            name: "GitCore",
            dependencies: [.product(name: "libgit2", package: "libgit2")]
        ),
        .testTarget(
            name: "GitCoreTests",
            dependencies: ["GitCore"]
        )
    ]
)
