import SwiftUI

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Friendly Compiler Language") {
                openWindow(id: HelpWindow.id)
            }
        }
    }
}
