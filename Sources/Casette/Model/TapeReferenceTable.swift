import Foundation
import FriendlyCompiler

/// User-facing tape references (`#57`) mapped to private Sage lookups.
///
/// Row numbers are derived from the visible tape order (1-based), but only the
/// most recent successful, reusable expressions are valid references. The
/// kernel stores those values in a private dict so a prompt like `factor #57`
/// compiles to Sage that can be evaluated normally.
struct TapeReferenceTable: Equatable, Sendable {
    enum Expansion: Equatable, Sendable {
        case success(String)
        case failure(CompileError)
    }

    static let variableName = "__casette_tape_refs"
    static let capacity = 20
    static let empty = TapeReferenceTable(entries: [:])

    var entries: [Int: String]

    func expandReferences(in input: String) -> Expansion {
        var output = ""
        output.reserveCapacity(input.count)

        var index = input.startIndex
        var quotedBy: Character?
        var escaped = false

        while index < input.endIndex {
            let character = input[index]

            if let quote = quotedBy {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == quote {
                    quotedBy = nil
                }
                index = input.index(after: index)
                continue
            }

            if character == "\"" || character == "'" {
                quotedBy = character
                output.append(character)
                index = input.index(after: index)
                continue
            }

            if character == "#" {
                let digitsStart = input.index(after: index)
                var digitsEnd = digitsStart
                while digitsEnd < input.endIndex, input[digitsEnd].isNumber {
                    digitsEnd = input.index(after: digitsEnd)
                }

                if digitsStart != digitsEnd {
                    let digits = String(input[digitsStart..<digitsEnd])
                    let rowNumber = Int(digits) ?? -1
                    guard entries[rowNumber] != nil else {
                        return .failure(CompileError(
                            message: "`#\(digits)` is not available on the tape.",
                            position: input[..<index].utf8.count,
                            suggestion: "Use one of the last \(Self.capacity) successful tape entries."
                        ))
                    }
                    output += "\(Self.variableName)[\(rowNumber)]"
                    index = digitsEnd
                    continue
                }
            }

            output.append(character)
            index = input.index(after: index)
        }

        return .success(output)
    }

    func assignmentCode(for rowNumber: Int) -> String? {
        guard let expression = entries[rowNumber] else { return nil }
        let retained = entries.keys.sorted().map(String.init).joined(separator: ", ")
        return """
        \(Self.variableName) = globals().get('\(Self.variableName)', {})
        \(Self.variableName)[\(rowNumber)] = (\(expression))
        for __casette_tape_key in list(\(Self.variableName)):
            if __casette_tape_key not in {\(retained)}:
                del \(Self.variableName)[__casette_tape_key]
        del __casette_tape_key
        """
    }
}
