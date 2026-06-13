import Foundation
import Testing
@testable import Casette

/// The V1.9 "remember UI layout" contract: the `@AppStorage` keys and the
/// `SidebarTab` raw values ARE the persisted vocabulary — pinned here so a
/// rename can't silently drop every user's saved layout. The round trip runs
/// through a private `UserDefaults` suite (never the real domain).
@Suite("UI layout persistence (V1.9)")
struct UILayoutPersistenceTests {
    @Test("SidebarTab raw values are the frozen persisted vocabulary")
    func sidebarTabRawValuesAreStable() {
        #expect(SidebarTab.symbols.rawValue == "symbols")
        #expect(SidebarTab.history.rawValue == "history")
        #expect(SidebarTab.inspector.rawValue == "inspector")
        #expect(SidebarTab.actions.rawValue == "actions")
    }

    @Test("stored tab decodes back; unknown/missing values fall back to Symbols")
    func storedTabDecodesWithFallback() {
        for tab in SidebarTab.allCases {
            #expect(UILayout.sidebarTab(fromStored: tab.rawValue) == tab)
        }
        #expect(UILayout.sidebarTab(fromStored: nil) == .symbols)
        #expect(UILayout.sidebarTab(fromStored: "settings") == .symbols)
        #expect(UILayout.sidebarTab(fromStored: "") == .symbols)
    }

    @Test("the layout round-trips through UserDefaults under the production keys")
    func layoutRoundTripsThroughDefaults() throws {
        let suite = "casette-layout-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // What RootView's @AppStorage writes…
        defaults.set(false, forKey: UILayout.sidebarVisibleKey)
        defaults.set(SidebarTab.history.rawValue, forKey: UILayout.sidebarTabKey)
        defaults.set(156.0, forKey: UILayout.inputPaneHeightKey)
        defaults.set(64.0, forKey: UILayout.sidebarTopPaneHeightKey)
        defaults.set(true, forKey: UILayout.showBuiltinSymbolsKey)

        // …is what a relaunch reads back.
        #expect(defaults.bool(forKey: UILayout.sidebarVisibleKey) == false)
        #expect(
            UILayout.sidebarTab(fromStored: defaults.string(forKey: UILayout.sidebarTabKey))
                == .history)
        #expect(defaults.double(forKey: UILayout.inputPaneHeightKey) == 156.0)
        #expect(defaults.double(forKey: UILayout.sidebarTopPaneHeightKey) == 64.0)
        #expect(defaults.bool(forKey: UILayout.showBuiltinSymbolsKey))
    }

    @Test("split dimensions clamp so both panes stay usable")
    func splitDimensionsClampToUsableRange() {
        #expect(
            UILayout.clampedSplitDimension(
                10,
                total: 500,
                minimumPrimary: 72,
                minimumSecondary: 180,
                divider: 8
            ) == 72
        )
        #expect(
            UILayout.clampedSplitDimension(
                400,
                total: 500,
                minimumPrimary: 72,
                minimumSecondary: 180,
                divider: 8
            ) == 312
        )
        #expect(
            UILayout.clampedSplitDimension(
                120,
                total: 500,
                minimumPrimary: 72,
                minimumSecondary: 180,
                divider: 8
            ) == 120
        )
    }
}
