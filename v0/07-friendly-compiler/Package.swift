// swift-tools-version:6.0
import PackageDescription

// V0.7 — Friendly Input Compiler.
//
// `FriendlyCompiler` is the SURVIVING artifact: a pure (no-I/O) library that
// turns forgiving command-shim input into Sage source, written to migrate into
// the app (V1.4 compiles on every keystroke/submit to show "Generated Sage"
// without round-tripping through the Python worker). `sagecalc-compile` is a
// thin CLI wrapper. Tests use swift-testing.
let package = Package(
    name: "FriendlyCompiler",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FriendlyCompiler", targets: ["FriendlyCompiler"]),
        .executable(name: "sagecalc-compile", targets: ["sagecalc-compile"]),
    ],
    targets: [
        .target(name: "FriendlyCompiler"),
        .executableTarget(
            name: "sagecalc-compile",
            dependencies: ["FriendlyCompiler"]
        ),
        .testTarget(
            name: "FriendlyCompilerTests",
            dependencies: ["FriendlyCompiler"]
        ),
    ]
)
