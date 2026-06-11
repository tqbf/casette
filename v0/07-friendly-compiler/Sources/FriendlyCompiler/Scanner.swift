// Lightweight structural scanning — NOT a math parser.
//
// Per the spec, we do not build a full expression parser. We only need enough
// structure to (a) validate balanced parens/brackets and (b) split a payload on
// top-level commas (commas not nested inside (), [], {}). Expression payloads
// are otherwise passed through verbatim.

import Foundation

enum Scanner {

    /// A balance / bracket problem found while scanning.
    struct BalanceError {
        enum Kind {
            case unclosed(Character)       // an opener that never closed
            case unexpectedClose(Character) // a closer with no matching opener
            case mismatched(open: Character, close: Character) // (..] etc.
        }
        let kind: Kind
        /// 0-based UTF-8 offset of the offending bracket.
        let position: Int
    }

    private static let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
    private static let closers: Set<Character> = [")", "]", "}"]

    /// Validate that all (), [], {} in `s` are balanced and correctly nested.
    /// Returns the first problem, or nil if balanced. Brackets inside string
    /// literals are intentionally NOT special-cased: Sage math input here does
    /// not use string literals, and treating quotes as significant would add a
    /// parser we deliberately don't want. (A raw-Sage string literal containing
    /// an unbalanced bracket would bypass before reaching command parsing.)
    static func balanceError(in s: String) -> BalanceError? {
        var stack: [(char: Character, pos: Int)] = []
        for (offset, ch) in s.utf8Offsets {
            if pairs[ch] != nil {
                stack.append((ch, offset))
            } else if closers.contains(ch) {
                guard let top = stack.popLast() else {
                    return BalanceError(kind: .unexpectedClose(ch), position: offset)
                }
                if pairs[top.char] != ch {
                    return BalanceError(kind: .mismatched(open: top.char, close: ch), position: offset)
                }
            }
        }
        if let leftover = stack.first {
            return BalanceError(kind: .unclosed(leftover.char), position: leftover.pos)
        }
        return nil
    }

    /// Split `s` on top-level commas (depth 0 w.r.t. (), [], {}), trimming each
    /// piece. Assumes `s` is already balanced (call `balanceError` first).
    static func splitTopLevelCommas(_ s: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for ch in s {
            if pairs[ch] != nil {
                depth += 1
                current.append(ch)
            } else if closers.contains(ch) {
                depth -= 1
                current.append(ch)
            } else if ch == "," && depth == 0 {
                parts.append(current.trimmedShim)
                current = ""
            } else {
                current.append(ch)
            }
        }
        parts.append(current.trimmedShim)
        return parts
    }
}

extension StringProtocol {
    /// Trim ASCII spaces/tabs (the only whitespace a single input line carries
    /// after newline stripping). Kept explicit so behavior is obvious.
    var trimmedShim: String {
        var sub = Substring(self)
        while let f = sub.first, f == " " || f == "\t" { sub = sub.dropFirst() }
        while let l = sub.last, l == " " || l == "\t" { sub = sub.dropLast() }
        return String(sub)
    }
}

extension String {
    /// Enumerate (utf8-offset, Character). Offsets are byte offsets so they line
    /// up with `CompileError.position` (a UTF-8 offset). For ASCII math input
    /// these equal character indices; for any multibyte char the bracket scan
    /// still advances correctly because we step the byte count per character.
    var utf8Offsets: [(Int, Character)] {
        var result: [(Int, Character)] = []
        var offset = 0
        for ch in self {
            result.append((offset, ch))
            offset += String(ch).utf8.count
        }
        return result
    }
}
