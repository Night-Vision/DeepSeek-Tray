// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DeepSeekTray",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DeepSeekTray", targets: ["DeepSeekTray"])
    ],
    targets: [
        .executableTarget(
            name: "DeepSeekTray",
            path: "Sources/DeepSeekTray"
        ),
        .testTarget(
            name: "DeepSeekTrayTests",
            dependencies: ["DeepSeekTray"],
            path: "Tests/DeepSeekTrayTests"
        )
    ]
)
