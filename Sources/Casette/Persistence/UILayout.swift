import Foundation

/// The `UserDefaults` keys behind the V1.9 "remember UI layout" criterion —
/// sidebar visibility and the selected sidebar tab, persisted via
/// `@AppStorage` in `RootView` (the standard macOS idiom for lightweight,
/// app-level UI state; the window frame itself is restored by the system's
/// window restoration for `WindowGroup` scenes).
///
/// Centralized so tests can pin the contract: the keys are stable, and
/// `SidebarTab`'s raw values are the persisted vocabulary (renaming a case
/// would silently drop every user's saved tab — the round-trip test catches
/// that).
///
/// V1.1 deliberately did NOT persist tab selection; the V1.9 spec ("remember
/// UI layout") supersedes that decision — the spec wins.
enum UILayout {
    static let sidebarVisibleKey = "sidebarVisible"
    static let sidebarTabKey = "sidebarTab"

    /// Decodes a stored tab raw value, falling back to the V1.1 default
    /// (Symbols) for an unknown/missing value.
    static func sidebarTab(fromStored rawValue: String?) -> SidebarTab {
        rawValue.flatMap(SidebarTab.init(rawValue:)) ?? .symbols
    }
}
