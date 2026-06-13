import Foundation

struct HelpSection: Identifiable, Equatable {
    var id: String { title }

    let title: String
    let summary: String
    let examples: [HelpExample]
}
