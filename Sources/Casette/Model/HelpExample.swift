import Foundation

struct HelpExample: Identifiable, Equatable {
    var id: String { command }

    let command: String
    let detail: String
    let sage: String
}
