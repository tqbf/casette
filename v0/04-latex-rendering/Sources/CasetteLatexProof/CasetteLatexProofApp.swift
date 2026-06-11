import SwiftUI

/// V0.4 proof app entry point. A standalone window that renders the math corpus.
/// Deliberately not wired to the main Casette app (that's V1.5).
@main
struct CasetteLatexProofApp: App {
    var body: some Scene {
        WindowGroup("Casette Math Proof") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}
