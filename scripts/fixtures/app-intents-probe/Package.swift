// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenoIntentProbe",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MenoIntentProbe", targets: ["MenoIntentProbe"])],
    targets: [.executableTarget(name: "MenoIntentProbe", path: "Sources")],
    swiftLanguageModes: [.v5]
)
