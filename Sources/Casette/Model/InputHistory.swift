import Foundation

/// Command history for the input pane — the session's submitted inputs, with
/// shell-style Up/Down navigation and the customary draft preservation: the
/// in-progress draft is stashed when navigation begins and restored when the
/// user comes back down past the newest entry.
///
/// Pure value type, no I/O — `ShellModel` owns one and maps Up/Down onto it.
struct InputHistory: Equatable, Sendable {
    /// Submitted inputs, oldest first.
    private(set) var entries: [String] = []
    /// Index of the entry currently recalled; nil while editing the live draft.
    private var cursor: Int?
    /// The in-progress draft, stashed when navigation begins.
    private var stashedDraft = ""

    /// Records a submitted input and resets navigation. Consecutive
    /// duplicates collapse (shell convention) so Up doesn't repeat itself.
    mutating func record(_ input: String) {
        if entries.last != input {
            entries.append(input)
        }
        cursor = nil
        stashedDraft = ""
    }

    /// Up: recall the previous (older) entry. The first step stashes the
    /// live draft. Returns nil at the oldest entry (or with no history) —
    /// the caller leaves the draft alone.
    mutating func recallPrevious(stashing draft: String) -> String? {
        guard !entries.isEmpty else { return nil }
        if let cursor {
            guard cursor > 0 else { return nil }
            self.cursor = cursor - 1
        } else {
            stashedDraft = draft
            cursor = entries.count - 1
        }
        return entries[cursor!]
    }

    /// The user edited the draft mid-navigation: end navigation and discard
    /// the stash (the edited text in the field IS the live draft now). The
    /// next Up starts from the newest entry again — standard shell behavior.
    mutating func endNavigation() {
        cursor = nil
        stashedDraft = ""
    }

    /// Down: move forward (newer). Past the newest entry it restores the
    /// stashed draft and ends navigation. Returns nil when not navigating.
    mutating func recallNext() -> String? {
        guard let cursor else { return nil }
        if cursor < entries.count - 1 {
            self.cursor = cursor + 1
            return entries[self.cursor!]
        }
        self.cursor = nil
        defer { stashedDraft = "" }
        return stashedDraft
    }

    /// True while an entry is recalled (navigation in progress).
    var isNavigating: Bool { cursor != nil }
}
