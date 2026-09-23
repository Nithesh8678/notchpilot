// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "NotchPilot", platforms: [.macOS(.v26)],
    products: [.executable(name: "NotchPilot", targets: ["NotchPilotApp"])],
    targets: [
        .target(name: "NotchPilotCore"),
        .executableTarget(name: "NotchPilotApp", dependencies: ["NotchPilotCore"]),
        .testTarget(name: "NotchPilotCoreTests", dependencies: ["NotchPilotCore"])
    ], swiftLanguageModes: [.v5]
)
