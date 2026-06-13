import Foundation

/// The small user-editable shape behind probability distribution commands.
/// Each command has one or two positional values plus a small canonical set of
/// named parameters. It renders friendly input, not Sage, and preserves
/// partially filled named fields (`n=`, `lambda=`) during formula-bar edits.
public struct StatsFormulaIR: Equatable, Sendable {
    public struct NamedField: Equatable, Sendable {
        public let key: String
        public let title: String
        public let prompt: String

        public init(key: String, title: String, prompt: String) {
            self.key = key
            self.title = title
            self.prompt = prompt
        }
    }

    public enum Kind: Equatable, Sendable, CaseIterable {
        case normalPDF, normalCDF, normalBetween, normalInv
        case binomialPMF, binomialCDF, binomialBetween, binomialAtMost, binomialAtLeast
        case poissonPMF, poissonCDF, poissonBetween, poissonAtMost, poissonAtLeast
        case exponentialPDF, exponentialCDF, exponentialBetween, exponentialInv
        case uniformPDF, uniformCDF, uniformBetween, uniformInv

        public var command: String {
            switch self {
            case .normalPDF: return "normal_pdf"
            case .normalCDF: return "normal_cdf"
            case .normalBetween: return "normal_between"
            case .normalInv: return "normal_inv"
            case .binomialPMF: return "binomial_pmf"
            case .binomialCDF: return "binomial_cdf"
            case .binomialBetween: return "binomial_between"
            case .binomialAtMost: return "binomial_at_most"
            case .binomialAtLeast: return "binomial_at_least"
            case .poissonPMF: return "poisson_pmf"
            case .poissonCDF: return "poisson_cdf"
            case .poissonBetween: return "poisson_between"
            case .poissonAtMost: return "poisson_at_most"
            case .poissonAtLeast: return "poisson_at_least"
            case .exponentialPDF: return "exponential_pdf"
            case .exponentialCDF: return "exponential_cdf"
            case .exponentialBetween: return "exponential_between"
            case .exponentialInv: return "exponential_inv"
            case .uniformPDF: return "uniform_pdf"
            case .uniformCDF: return "uniform_cdf"
            case .uniformBetween: return "uniform_between"
            case .uniformInv: return "uniform_inv"
            }
        }

        public var title: String {
            switch self {
            case .normalPDF: return "NORMAL PDF"
            case .normalCDF: return "NORMAL CDF"
            case .normalBetween: return "NORMAL RANGE"
            case .normalInv: return "NORMAL INV"
            case .binomialPMF: return "BINOMIAL PMF"
            case .binomialCDF: return "BINOMIAL CDF"
            case .binomialBetween: return "BINOMIAL RANGE"
            case .binomialAtMost: return "BINOMIAL <="
            case .binomialAtLeast: return "BINOMIAL >="
            case .poissonPMF: return "POISSON PMF"
            case .poissonCDF: return "POISSON CDF"
            case .poissonBetween: return "POISSON RANGE"
            case .poissonAtMost: return "POISSON <="
            case .poissonAtLeast: return "POISSON >="
            case .exponentialPDF: return "EXP PDF"
            case .exponentialCDF: return "EXP CDF"
            case .exponentialBetween: return "EXP RANGE"
            case .exponentialInv: return "EXP INV"
            case .uniformPDF: return "UNIFORM PDF"
            case .uniformCDF: return "UNIFORM CDF"
            case .uniformBetween: return "UNIFORM RANGE"
            case .uniformInv: return "UNIFORM INV"
            }
        }

        public var positionalTitles: [String] {
            switch self {
            case .normalBetween, .binomialBetween, .poissonBetween,
                 .exponentialBetween, .uniformBetween:
                return ["a", "b"]
            case .normalInv, .exponentialInv, .uniformInv:
                return ["p"]
            case .binomialPMF, .binomialCDF, .binomialAtMost, .binomialAtLeast,
                 .poissonPMF, .poissonCDF, .poissonAtMost, .poissonAtLeast:
                return ["k"]
            default:
                return ["x"]
            }
        }

        public var positionalPrompts: [String] {
            switch self {
            case .normalBetween: return ["-1", "1"]
            case .binomialBetween: return ["3", "7"]
            case .poissonBetween: return ["1", "4"]
            case .exponentialBetween: return ["1", "2"]
            case .uniformBetween: return [".2", ".8"]
            case .normalInv, .exponentialInv, .uniformInv: return [".95"]
            case .binomialAtLeast: return ["8"]
            case .poissonAtLeast: return ["5"]
            case .binomialPMF, .binomialCDF, .binomialAtMost: return ["3"]
            case .poissonPMF, .poissonCDF, .poissonAtMost: return ["2"]
            default: return ["1"]
            }
        }

        public var namedFields: [NamedField] {
            switch self {
            case .normalPDF, .normalCDF, .normalBetween, .normalInv:
                return [
                    NamedField(key: "mean", title: "mean", prompt: "0"),
                    NamedField(key: "sd", title: "sd", prompt: "1"),
                ]
            case .binomialPMF, .binomialCDF, .binomialBetween,
                 .binomialAtMost, .binomialAtLeast:
                return [
                    NamedField(key: "n", title: "n", prompt: "10"),
                    NamedField(key: "p", title: "p", prompt: ".5"),
                ]
            case .poissonPMF, .poissonCDF, .poissonBetween,
                 .poissonAtMost, .poissonAtLeast:
                return [NamedField(key: "lambda", title: "lambda", prompt: "3")]
            case .exponentialPDF, .exponentialCDF, .exponentialBetween, .exponentialInv:
                return [NamedField(key: "rate", title: "rate", prompt: "2")]
            case .uniformPDF, .uniformCDF, .uniformBetween, .uniformInv:
                return [
                    NamedField(key: "min", title: "min", prompt: "0"),
                    NamedField(key: "max", title: "max", prompt: "1"),
                ]
            }
        }

        fileprivate init?(_ keyword: FriendlyCompiler.Keyword) {
            switch keyword {
            case .normalPDF: self = .normalPDF
            case .normalCDF: self = .normalCDF
            case .normalBetween: self = .normalBetween
            case .normalInv: self = .normalInv
            case .binomialPMF: self = .binomialPMF
            case .binomialCDF: self = .binomialCDF
            case .binomialBetween: self = .binomialBetween
            case .binomialAtMost: self = .binomialAtMost
            case .binomialAtLeast: self = .binomialAtLeast
            case .poissonPMF: self = .poissonPMF
            case .poissonCDF: self = .poissonCDF
            case .poissonBetween: self = .poissonBetween
            case .poissonAtMost: self = .poissonAtMost
            case .poissonAtLeast: self = .poissonAtLeast
            case .exponentialPDF: self = .exponentialPDF
            case .exponentialCDF: self = .exponentialCDF
            case .exponentialBetween: self = .exponentialBetween
            case .exponentialInv: self = .exponentialInv
            case .uniformPDF: self = .uniformPDF
            case .uniformCDF: self = .uniformCDF
            case .uniformBetween: self = .uniformBetween
            case .uniformInv: self = .uniformInv
            default: return nil
            }
        }
    }

    public var kind: Kind
    public var positional: [String]
    public var named: [String: String]

    public init(kind: Kind, positional: [String] = [], named: [String: String] = [:]) {
        self.kind = kind
        self.positional = positional
        self.named = named
    }

    public static func parse(_ rawInput: String) -> StatsFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              let kind = Kind(command.keyword)
        else { return nil }

        let body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        let parts = Scanner.splitTopLevelCommas(body).map { $0.trimmedShim }
        let allowed = Set(kind.namedFields.map(\.key))
        var positional: [String] = []
        var named: [String: String] = [:]

        for part in parts {
            if let assignment = namedArgument(part), allowed.contains(assignment.name) {
                named[assignment.name] = assignment.value
            } else {
                positional.append(part)
            }
        }

        return StatsFormulaIR(kind: kind, positional: positional, named: named)
    }

    public var friendlyInput: String {
        let trimmedPositional = positional.map { $0.trimmedShim }
        let lastPositional = trimmedPositional.lastIndex { !$0.isEmpty }
        let renderedPositional = lastPositional.map {
            Array(trimmedPositional[...$0])
        } ?? []
        let renderedNamed = kind.namedFields.compactMap { field -> String? in
            guard let value = named[field.key] else { return nil }
            return "\(field.key)=\(value.trimmedShim)"
        }
        let parts = renderedPositional + renderedNamed
        guard !parts.isEmpty else { return kind.command }
        return "\(kind.command) \(parts.joined(separator: ", "))"
    }

    private static func namedArgument(_ text: String) -> (name: String, value: String)? {
        let parts = text.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let name = String(parts[0]).trimmedShim
        guard Variables.isPlausibleVariable(name) else { return nil }
        return (name: name, value: String(parts[1]).trimmedShim)
    }
}
