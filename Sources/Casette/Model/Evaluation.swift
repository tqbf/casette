import Foundation

/// The outcome of one kernel evaluation: how it ended, the render-ready
/// envelope, and how long it took.
///
/// This is the V1.3 seam: `SageKernel` will produce an `Evaluation` from the
/// worker's wire response (via `PersistedEnvelope(workerResponse:)` +
/// `RowStatus(workerResponse:)`), and the model applies it to the pending row
/// with `ShellModel.complete(rowID:with:)`. It is deliberately NOT `Codable` —
/// what persists is the `SessionRow` it is applied to.
struct Evaluation: Equatable, Sendable {
    /// How the evaluation ended: `.ok`, `.error`, or `.interrupted`.
    /// (`.running` would be meaningless here — an `Evaluation` is an outcome.)
    var status: RowStatus
    /// The render-ready result envelope; nil only when the worker died before
    /// producing one (a crashed eval still ends the row as `.error`).
    var result: PersistedEnvelope?
    /// Wall-clock duration in seconds, if measured.
    var duration: TimeInterval?
}
