// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Casette",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        // The V0.4-proven math engine (plans/MATH-RENDERING.md): native Core
        // Text typesetting, fully offline, no JS bridge. Same pin as the
        // v0/04 proof. It renders every spec + real-worker LaTeX case; its
        // one gap (Sage's `array` matrices) is handled by the lifted
        // `SageLatexNormalizer` rewrite. Used ONLY behind the `MathRenderer`
        // abstraction — no view imports SwiftMath directly.
        .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.3"),
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
            dependencies: [
                "FriendlyCompiler",
                .product(name: "SwiftMath", package: "SwiftMath"),
            ],
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
