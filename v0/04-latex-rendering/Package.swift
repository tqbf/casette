// swift-tools-version:6.0
import PackageDescription

// V0.4 — LaTeX rendering proof. A standalone SwiftPM executable, deliberately
// NOT entangled with the main Casette app. It proves the macOS UI can render the
// worker's `latex` envelope field beautifully and reliably.
//
// Renderer choice: LaTeXSwiftUI (MathJax-in-JavaScriptCore, fully offline, native
// SwiftUI view). The product decision named "Textual" — research (see
// plans/MATH-RENDERING.md) disqualified it: gonzalezreal/textual has a macOS 15
// floor (we need 14) and only does markdown-embedded math via an immature engine.
// LaTeXSwiftUI is the chosen path, kept behind a `MathRenderer` abstraction so we
// can swap engines without touching the app.
let package = Package(
    name: "CasetteLatexProof",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        // PRIMARY engine: SwiftMath — native Core Text typesetting, fully offline,
        // no JS bridge. Renders the spec's braced-script LaTeX (`\sum_{n=0}^{\infty}`),
        // bmatrix, partials, and set-builder that LaTeXSwiftUI/MathJax could not in
        // this environment (see PROBLEMS.md). Its only gap is Sage's `\begin{array}`
        // matrix form, which we transform to `pmatrix` at the normalization boundary.
        .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.3"),
        // Kept as a documented ALTERNATIVE behind the MathRenderer abstraction:
        // LaTeXSwiftUI (MathJax/JavaScriptCore). Handles Sage's `array` natively but
        // fails on braced sub/superscripts here. See plans/MATH-RENDERING.md.
        .package(url: "https://github.com/colinc86/LaTeXSwiftUI", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "CasetteLatexProof",
            dependencies: [
                .product(name: "SwiftMath", package: "SwiftMath"),
                .product(name: "LaTeXSwiftUI", package: "LaTeXSwiftUI"),
            ],
            path: "Sources/CasetteLatexProof"
        ),
    ]
)
