import Foundation

/// The small user-editable shape behind Casette's limit formula bar.
///
/// `limit EXPR, VAR->POINT` with an optional `left`/`right` direction. Parsing
/// is tolerant: a half-typed approach leaves `variable`/`point` empty so the bar
/// still shows as the user types. Like the other formula IRs this renders back
/// to friendly input, not Sage; `#14` tape references stay intact until the
/// app's compile boundary.
public struct LimitFormulaIR: Equatable, Sendable {
    /// Which side the limit approaches from. `both` is the default two-sided
    /// limit (no direction clause rendered).
    public enum Direction: Equatable, Sendable, CaseIterable {
        case both
        case left
        case right
    }

    public var expression: String
    public var variable: String
    public var point: String
    public var direction: Direction

    public init(
        expression: String,
        variable: String = "",
        point: String = "",
        direction: Direction = .both
    ) {
        self.expression = expression
        self.variable = variable
        self.point = point
        self.direction = direction
    }

    public static func parse(_ rawInput: String) -> LimitFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              command.keyword == .limit
        else { return nil }

        let body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        let parts = Scanner.splitTopLevelCommas(body)
        let expression = parts.first?.trimmedShim ?? ""

        var approachParts = Array(parts.dropFirst())
        var direction: Direction = .both
        // A trailing standalone `left`/`right` part names the direction; any
        // other trailing word is left in the approach (it just won't parse a
        // variable, which keeps the bar visible while the user types).
        if approachParts.count >= 2 {
            switch approachParts[approachParts.count - 1].trimmedShim.lowercased() {
            case "left": direction = .left; approachParts.removeLast()
            case "right": direction = .right; approachParts.removeLast()
            default: break
            }
        }

        let approach = approachParts.joined(separator: ", ").trimmedShim
        var variable = ""
        var point = ""
        if let arrow = approach.range(of: "->") {
            variable = String(approach[approach.startIndex..<arrow.lowerBound]).trimmedShim
            point = String(approach[arrow.upperBound...]).trimmedShim
        } else {
            // No arrow yet: treat the whole approach as a nascent variable so the
            // var token shows what the user has typed.
            variable = approach
        }

        return LimitFormulaIR(
            expression: expression,
            variable: variable,
            point: point,
            direction: direction)
    }

    public var friendlyInput: String {
        let trimmedExpression = expression.trimmedShim
        var input = trimmedExpression.isEmpty ? "limit" : "limit \(trimmedExpression)"

        let v = variable.trimmedShim
        let p = point.trimmedShim
        if !v.isEmpty || !p.isEmpty || direction != .both {
            input += ", \(v)->\(p)"
        }
        switch direction {
        case .both: break
        case .left: input += ", left"
        case .right: input += ", right"
        }

        return input
    }
}
