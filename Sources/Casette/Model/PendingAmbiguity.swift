import Foundation

/// An ambiguous submission awaiting the user's choice: the raw input plus the
/// compiler's candidate Sage readings (`solve x*y = 1` → solve for x / for y).
/// Presented as a picker anchored to the input pane; the chosen candidate
/// evaluates. Transient UI state — never persisted.
struct PendingAmbiguity: Identifiable, Equatable {
    let id = UUID()
    /// The raw input as typed (becomes the row's `input` once resolved).
    let raw: String
    /// One generated-Sage string per reading, in the compiler's order.
    let candidates: [String]
    /// Whether the submission should advance (clear the draft) once resolved —
    /// false when it came from ⌘↩ (evaluate without advancing).
    let advances: Bool
}
