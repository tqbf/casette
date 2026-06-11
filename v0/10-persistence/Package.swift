// swift-tools-version:6.0
import PackageDescription

// V0.10 — Session Tape Persistence-Lite.
//
// `SessionStore` is the SURVIVING artifact: the prototype of V1.2's session
// model (`Session` / `SessionRow` / `PersistedEnvelope` / `PersistedArtifact` /
// provenance) AND V1.9's persistence (atomic incremental save, restore-without-
// Sage, optional replay into a fresh worker, graceful artifact degradation,
// corruption/version robustness). The Codable types are designed to migrate
// into the app *verbatim*.
//
// `casette-tape` is the CLI/harness that drives the V0.10 proof: it runs a real
// worker session, persists the tape incrementally, "relaunches" (a fresh load
// with Sage genuinely not spawned), replays into a fresh worker, and exercises
// the missing-artifact and robustness paths.
//
// WorkerProcess.swift + LineReader.swift are COPIED from v0/09-sage-doctor
// (the proven Swift process-control pattern). The duplication is intentional —
// v0/09 is frozen evidence and must not be refactored. V1 should UNIFY these
// into one `SageKernel` (see plans/SESSION-FORMAT.md "V1 integration notes").
//
// Tests use swift-testing and cover the PURE logic (codec round-trip, schema-
// version refusal, corruption quarantine, provenance/supersede policy, artifact
// liveness) with no Sage dependency; the worker-dependent replay proof lives in
// the CLI harness.
let package = Package(
    name: "SessionStore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SessionStore", targets: ["SessionStore"]),
        .executable(name: "casette-tape", targets: ["casette-tape"]),
    ],
    targets: [
        .target(name: "SessionStore"),
        .executableTarget(
            name: "casette-tape",
            dependencies: ["SessionStore"]
        ),
        .testTarget(
            name: "SessionStoreTests",
            dependencies: ["SessionStore"]
        ),
    ]
)
