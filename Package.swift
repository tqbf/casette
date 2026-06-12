// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Casette",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        // The friendly input compiler — the V0.7 pure library, lifted from
        // v0/07-friendly-compiler (library files byte-identical to the frozen
        // proof; app-side additions live in FriendlyCompiler+App.swift only).
        .target(
            name: "FriendlyCompiler",
            path: "Sources/FriendlyCompiler"
        ),
        .executableTarget(
            name: "Casette",
            dependencies: ["FriendlyCompiler"],
            path: "Sources/Casette"
        ),
        .testTarget(
            name: "CasetteTests",
            dependencies: ["Casette"],
            path: "Tests/CasetteTests"
        ),
        // The lifted library's own 69-test suite, byte-identical to v0/07.
        .testTarget(
            name: "FriendlyCompilerTests",
            dependencies: ["FriendlyCompiler"],
            path: "Tests/FriendlyCompilerTests"
        ),
    ]
)
