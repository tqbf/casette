import Foundation
import SwiftMath

/// Memoizes the per-LaTeX-string work that would otherwise run on every
/// SwiftUI body evaluation: the `SageLatexNormalizer` regex rewrite and the
/// SwiftMath parse validation. Tape rows re-render on hover/selection and
/// `LazyVStack` re-creates rows while scrolling, so without this the same
/// string is normalized + parsed over and over on the main thread
/// (MATH-RENDERING.md's caching recommendation; PROBLEMS.md: rendering must
/// never hitch the tape).
///
/// `@MainActor` because every caller (view bodies, `MathContent.choose`) is,
/// and `MTMathListBuilder` is engine code we don't send across actors.
@MainActor
enum MathRenderCache {
    struct Entry {
        /// The engine-ready (normalized) LaTeX.
        let normalized: String
        /// Did SwiftMath's parser accept it? `false` → render `plain` instead.
        let parses: Bool
    }

    private static var storage: [String: Entry] = [:]
    /// Hard cap so an unbounded session can't grow the cache forever. On
    /// overflow the whole cache resets — re-filling is cheap and simple beats
    /// clever (SWIFTUI-RULES §3.2: no self-patching caches).
    private static let capacity = 1024

    static func entry(for latex: String) -> Entry {
        if let cached = storage[latex] { return cached }
        let normalized = SageLatexNormalizer.normalizeForSwiftMath(latex)
        var parses = false
        if !SageLatexNormalizer.isUnsafeForSwiftMathLayout(normalized) {
            var error: NSError?
            _ = MTMathListBuilder.build(fromString: normalized, error: &error)
            parses = error == nil
        }
        let entry = Entry(normalized: normalized, parses: parses)
        if storage.count >= capacity { storage.removeAll(keepingCapacity: true) }
        storage[latex] = entry
        return entry
    }
}
