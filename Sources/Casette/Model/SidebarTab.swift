import Foundation

/// The four tabs of the right sidebar (INITIAL.md V1.1).
enum SidebarTab: String, CaseIterable, Identifiable, Sendable {
    case symbols
    case history
    case inspector
    case actions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .symbols: "Symbols"
        case .history: "History"
        case .inspector: "Inspector"
        case .actions: "Actions"
        }
    }

    var systemImage: String {
        switch self {
        case .symbols: "x.squareroot"
        case .history: "clock"
        case .inspector: "info.circle"
        case .actions: "bolt"
        }
    }
}
