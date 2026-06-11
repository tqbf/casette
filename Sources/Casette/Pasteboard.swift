import AppKit

/// Tiny clipboard helper so context menus share one copy path.
@MainActor
enum Pasteboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
