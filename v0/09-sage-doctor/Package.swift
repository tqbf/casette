// swift-tools-version:6.0
import PackageDescription

// V0.9 — Sage Doctor / Environment Discovery.
//
// `SageDoctor` is the SURVIVING artifact: a library that discovers a
// user-installed Sage, drives the canonical worker end-to-end, and reports
// status. It migrates into the app for V1.10 (in-app "Sage Doctor" settings
// pane). `sage-doctor` is the CLI that drives it for the V0.9 proof.
//
// This package is ALSO the first proof that Swift (not Python) can spawn,
// drive, interrupt, and hard-kill `sage -python worker.py` — a dry run for
// V1.3's SageKernel. The process-control lessons from PROBLEMS.md are applied
// in Swift here: launch in a new session / process group, hard-kill the GROUP,
// target SIGINT at the worker's real pid from the ready banner.
//
// Tests use swift-testing and cover the PURE logic (path-search ordering,
// version parsing/policy, report formatting) with no Sage dependency.
let package = Package(
    name: "SageDoctor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SageDoctor", targets: ["SageDoctor"]),
        .executable(name: "sage-doctor", targets: ["sage-doctor"]),
    ],
    targets: [
        .target(name: "SageDoctor"),
        .executableTarget(
            name: "sage-doctor",
            dependencies: ["SageDoctor"]
        ),
        .testTarget(
            name: "SageDoctorTests",
            dependencies: ["SageDoctor"]
        ),
    ]
)
