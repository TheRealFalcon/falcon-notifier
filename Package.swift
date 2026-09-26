// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notifier",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Notifier", targets: ["Notifier"])],
    targets: [
        .target(name: "NotifierCore"),
        .executableTarget(name: "Notifier", dependencies: ["NotifierCore"]),
    ]
)
