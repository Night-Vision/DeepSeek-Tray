// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DeepSeekTray",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DeepSeekTray", targets: ["DeepSeekTray"]),
        .executable(name: "DeepSeekTrayTests", targets: ["DeepSeekTrayTests"])
    ],
    targets: [
        .executableTarget(
            name: "DeepSeekTray",
            path: "Sources/DeepSeekTray"
        ),
        .executableTarget(
            name: "DeepSeekTrayTests",
            path: "Tests/DeepSeekTrayTests"
        )
    ]
)
