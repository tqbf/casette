import AppKit

/// Tiny clipboard helper so context menus share one copy path.
@MainActor
enum Pasteboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Copies an image (the plot card's Copy Image — V1.7). `writeObjects`
    /// puts the bitmap on the pasteboard in the standard image flavors, so
    /// Preview/Pages/etc. can paste it.
    static func copy(image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}
