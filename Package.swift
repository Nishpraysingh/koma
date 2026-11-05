// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MihonMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MihonMac", targets: ["MihonMac"])],
    targets: [
        .executableTarget(name: "MihonMac", path: "Sources/MihonMac"),
        .testTarget(name: "MihonMacTests", dependencies: ["MihonMac"], path: "Tests/MihonMacTests"),
    ],
    swiftLanguageModes: [.v5]
)
