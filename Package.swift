// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SumoKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SumoKit", targets: ["SumoKit"]),
        .executable(name: "SumoGUIMac", targets: ["SumoGUIMac"]),
    ],
    targets: [
        .target(
            name: "SumoKit",
            path: "Sources/SumoKit"
        ),
        .executableTarget(
            name: "SumoGUIMac",
            dependencies: ["SumoKit"],
            path: "Sources/SumoGUIMac",
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "NetParseBenchmark",
            dependencies: ["SumoKit"],
            path: "Sources/NetParseBenchmark"
        ),
        .testTarget(
            name: "SumoKitTests",
            dependencies: ["SumoKit"],
            path: "Tests/SumoKitTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SumoGUIMacTests",
            dependencies: ["SumoGUIMac", "SumoKit"],
            path: "Tests/SumoGUIMacTests"
        ),
    ]
)
