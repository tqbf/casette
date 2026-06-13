import Foundation

/// Structured matrix cells for the pop-out table view. The values come from
/// Sage on demand, not from the abbreviated tape rendering.
struct MatrixTableData: Decodable, Equatable, Sendable {
    let rows: [[String]]
    let rowCount: Int
    let columnCount: Int

    enum CodingKeys: String, CodingKey {
        case rows
        case rowCount = "row_count"
        case columnCount = "column_count"
    }

    var isEmpty: Bool {
        rowCount == 0 || columnCount == 0
    }
}
