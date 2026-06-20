// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "typeless-relay",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "typeless-proxy-relay", targets: ["TypelessRelay"])
    ],
    targets: [
        .executableTarget(name: "TypelessRelay", path: "Sources/TypelessRelay")
    ]
)
