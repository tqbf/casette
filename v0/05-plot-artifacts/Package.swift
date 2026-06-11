// swift-tools-version:6.0
import PackageDescription

// V0.5 — Plot/artifact pipeline proof (viewer side). A standalone SwiftPM
// executable, deliberately NOT entangled with the main Casette app. It loads the
// artifact files the Python harness produced (SVG + PNG plots saved by the Sage
// worker) and renders them in a scrolling list, proving the macOS UI can display
// worker-generated plot artifacts. Integration into the real app is V1.7.
//
// No third-party dependencies: SVG and PNG both load through AppKit's NSImage
// (SVG via the system _NSSVGImageRep, available macOS 14+; PNG via
// NSBitmapImageRep). Part of the V0.5 finding is *which* of those is reliable on
// the macOS-14 floor — the viewer renders both and lets you toggle per row.
let package = Package(
    name: "CasettePlotProof",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "CasettePlotProof",
            path: "Sources/CasettePlotProof"
        ),
    ]
)
