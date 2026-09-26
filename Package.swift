// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "falcon-notifier",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "falcon-notifier", targets: ["FalconNotifier"])],
    targets: [
        .target(name: "FalconNotifierCore"),
        .executableTarget(name: "FalconNotifier", dependencies: ["FalconNotifierCore"]),
    ]
)
