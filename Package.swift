// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentSoma",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "agentsoma", targets: ["AgentSoma"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.5.0")
    ],
    targets: [
        .target(name: "AgentSomaCore"),
        .executableTarget(name: "AgentSoma", dependencies: [
            "AgentSomaCore", .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]),
        .testTarget(name: "AgentSomaCoreTests", dependencies: ["AgentSomaCore"])
    ]
)
