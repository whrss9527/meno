// swift-tools-version: 6.0
import PackageDescription

// `MenoCore` holds the platform-independent logic (models, planning, matching)
// and builds on any platform so it can be unit-tested anywhere. The app target
// depends on AppKit and is only added when building on macOS.

var products: [Product] = [
    .library(name: "MenoCore", targets: ["MenoCore"]),
]

var targets: [Target] = [
    .target(
        name: "MenoCore",
        dependencies: [.product(name: "FritCore", package: "Frit")],
        path: "Sources/MenoCore",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
        name: "MenoCoreTests",
        dependencies: ["MenoCore", .product(name: "FritCore", package: "Frit")],
        path: "Tests/MenoCoreTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "Meno", targets: ["Meno"]))
targets.append(
    .executableTarget(
        name: "Meno",
        dependencies: ["MenoCore", .product(name: "FritCore", package: "Frit")],
        path: "Sources/Meno",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("ApplicationServices"),
            .linkedFramework("Carbon"),
            .linkedFramework("CoreAudio"),
            .linkedFramework("CoreMediaIO"),
            .linkedFramework("IOKit"),
            .linkedFramework("ServiceManagement"),
        ]
    )
)
#endif

let package = Package(
    name: "Meno",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: [
        .package(url: "https://github.com/whrss9527/Frit", revision: "697eba13b7edc659d71e4a4b0d10b8a149390f25"),
    ],
    targets: targets,
    swiftLanguageModes: [.v5]
)
