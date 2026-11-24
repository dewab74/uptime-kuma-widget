// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KumaKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KumaKit", targets: ["KumaKit"]),
        .library(name: "KumaUI", targets: ["KumaUI"]),
    ],
    targets: [
        .target(name: "KumaKit"),
        // SwiftUI pieces the menu bar app and the widget draw the same way.
        .target(name: "KumaUI", dependencies: ["KumaKit"]),
        // Development tool: renders the widget to PNG (see its main.swift).
        .executableTarget(name: "kuma-render", dependencies: ["KumaKit", "KumaUI"]),
        .testTarget(
            name: "KumaKitTests",
            dependencies: ["KumaKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
