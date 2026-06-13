import AppKit
import SwiftUI

@MainActor
enum MatrixTableWindowPresenter {
    private static var windows: [NSWindow] = []
    private static var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    static func show(table: MatrixTableData, title: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: MatrixTableWindowView(title: title, table: table) { [weak window] in
                window?.close()
            }
        )
        retainUntilClosed(window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func retainUntilClosed(_ window: NSWindow) {
        windows.append(window)
        let id = ObjectIdentifier(window)
        closeObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                windows.removeAll { $0 === window }
                if let observer = closeObservers.removeValue(forKey: id) {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
    }
}
