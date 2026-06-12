import Foundation

/// What the live compile of the current draft means for the preview line
/// under the input field — the view-facing summary of `CompiledInput.compile`
/// recomputed on every keystroke (the compiler is pure and microsecond-fast,
/// so friendly → Sage is always inspectable BEFORE submitting).
enum DraftPreview: Equatable {
    /// Nothing to preview (empty draft).
    case empty
    /// The input bypasses as raw Sage, untouched.
    case rawSage
    /// A friendly command compiled; the generated Sage to display.
    case generated(String)
    /// The friendly input is malformed; shown inline, submission is refused.
    case issue(message: String, suggestion: String?)
    /// The input has several readings; Return offers the candidates.
    case ambiguous(count: Int)
}
