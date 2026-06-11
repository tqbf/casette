import SwiftUI

/// V0.5 proof app entry point. A standalone window that renders the plot
/// artifacts the Sage worker produced. Deliberately not wired to the main
/// Casette app (that integration is V1.7).
@main
struct CasettePlotProofApp: App {
    var body: some Scene {
        WindowGroup("Casette Plot Proof") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}
