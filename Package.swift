// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Casette",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "Casette",
            path: "Sources/Casette"
        ),
        .testTarget(
            name: "CasetteTests",
            dependencies: ["Casette"],
            path: "Tests/CasetteTests"
        ),
    ]
)
