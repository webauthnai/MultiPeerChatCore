// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiPeerChatCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "MultiPeerChatCore",
            targets: ["MultiPeerChatCore"]
        )
    ],
    dependencies: [
        .package(name: "DogTagKit", path: "https://github.com/webauthnai/DogTagKit.git")
    ],
    targets: [
        .target(
            name: "MultiPeerChatCore",
            dependencies: [.product(name: "DogTagKit", package: "DogTagKit")]
        ),
        .testTarget(
            name: "MultiPeerChatTests",
            dependencies: ["MultiPeerChatCore"]
        )
    ]
) 
