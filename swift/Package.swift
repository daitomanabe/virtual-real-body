// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VirtualRealBody",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VirtualRealBody", targets: ["VirtualRealBody"])
    ],
    dependencies: [
        .package(path: "../external/Satin")
    ],
    targets: [
        .executableTarget(
            name: "VirtualRealBody",
            dependencies: ["Satin"],
            path: "Sources/VirtualRealBody",
            resources: [.process("Shaders")]
        )
    ]
)
