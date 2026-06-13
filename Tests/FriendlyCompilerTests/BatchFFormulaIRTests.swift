import Testing
@testable import FriendlyCompiler

// Batch F completion-UI IRs: `var`, `assume`, the binary number-theory family
// (`choose`, `gcd`, `lcm`), and the new unary kinds (`factorial`, `is_prime`,
// `factor_integer`, `mean`). Like the earlier batches these IRs render back to
// FRIENDLY INPUT, never Sage, and preserve `#ROW` tape references verbatim
// (docs/COMPLETION-UI.md).

@Suite("Var formula IR")
struct VarFormulaIRTests {
    @Test func parsesNames() {
        guard let ir = VarFormulaIR.parse("var x y z") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.names == "x y z")
        #expect(ir.friendlyInput == "var x y z")
    }

    @Test func parsesBareCommand() {
        guard let ir = VarFormulaIR.parse("var") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.names.isEmpty)
        #expect(ir.friendlyInput == "var")
    }

    @Test func roundTripStability() {
        guard var ir = VarFormulaIR.parse("var") else {
            Issue.record("expected parse"); return
        }
        ir.names = "a b c"
        let rendered = ir.friendlyInput
        #expect(rendered == "var a b c")
        #expect(VarFormulaIR.parse(rendered) == ir)
    }

    // The assignment form `var = 3` is NOT the declaration command.
    @Test func assignmentDoesNotMatch() {
        #expect(VarFormulaIR.parse("var = 3") == nil)
    }

    @Test func preservesRowReference() {
        guard let ir = VarFormulaIR.parse("var #4") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.names == "#4")
        #expect(ir.friendlyInput == "var #4")
    }

    @Test func rejectsNonVar() {
        #expect(VarFormulaIR.parse("factor x^2") == nil)
        #expect(VarFormulaIR.parse("var('x')") == nil)
    }
}

@Suite("Assume formula IR")
struct AssumeFormulaIRTests {
    @Test func parsesComparison() {
        guard let ir = AssumeFormulaIR.parse("assume x > 0") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.condition == "x > 0")
        #expect(ir.friendlyInput == "assume x > 0")
    }

    @Test func parsesProperty() {
        guard let ir = AssumeFormulaIR.parse("assume x real") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.condition == "x real")
        #expect(ir.friendlyInput == "assume x real")
    }

    @Test func parsesBareCommand() {
        guard let ir = AssumeFormulaIR.parse("assume") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.condition.isEmpty)
        #expect(ir.friendlyInput == "assume")
    }

    @Test func roundTripStability() {
        guard var ir = AssumeFormulaIR.parse("assume") else {
            Issue.record("expected parse"); return
        }
        ir.condition = "n >= 1"
        let rendered = ir.friendlyInput
        #expect(rendered == "assume n >= 1")
        #expect(AssumeFormulaIR.parse(rendered) == ir)
    }

    @Test func rejectsNonAssume() {
        #expect(AssumeFormulaIR.parse("factor x^2") == nil)
    }
}

@Suite("Binary formula IR")
struct BinaryFormulaIRTests {
    @Test func parsesChoose() {
        guard let ir = BinaryFormulaIR.parse("choose 10, 3") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.kind == .choose)
        #expect(ir.first == "10")
        #expect(ir.second == "3")
        #expect(ir.friendlyInput == "choose 10, 3")
    }

    @Test func parsesGcdTwoValues() {
        guard let ir = BinaryFormulaIR.parse("gcd 12, 18") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.kind == .gcd)
        #expect(ir.first == "12")
        #expect(ir.second == "18")
        #expect(ir.friendlyInput == "gcd 12, 18")
    }

    // Extra clauses re-join into `second` verbatim so nothing is lost.
    @Test func extraClausesRideInSecond() {
        guard let ir = BinaryFormulaIR.parse("gcd 12, 18, 24") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.first == "12")
        #expect(ir.second == "18, 24")
        #expect(ir.friendlyInput == "gcd 12, 18, 24")
        #expect(BinaryFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func bracketedListLeavesSecondEmpty() {
        guard let ir = BinaryFormulaIR.parse("lcm [12, 18, 24]") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.kind == .lcm)
        #expect(ir.first == "[12, 18, 24]")
        #expect(ir.second.isEmpty)
        #expect(ir.friendlyInput == "lcm [12, 18, 24]")
    }

    @Test func bareCommand() {
        guard let ir = BinaryFormulaIR.parse("choose") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.first.isEmpty)
        #expect(ir.second.isEmpty)
        #expect(ir.friendlyInput == "choose")
    }

    @Test func omitsSecondWhenEmpty() {
        guard var ir = BinaryFormulaIR.parse("gcd") else {
            Issue.record("expected parse"); return
        }
        ir.first = "12"
        #expect(ir.friendlyInput == "gcd 12")
    }

    @Test func roundTripStability() {
        guard var ir = BinaryFormulaIR.parse("choose") else {
            Issue.record("expected parse"); return
        }
        ir.first = "10"
        ir.second = "3"
        let rendered = ir.friendlyInput
        #expect(rendered == "choose 10, 3")
        #expect(BinaryFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesRowReference() {
        guard let ir = BinaryFormulaIR.parse("gcd #2, #3") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.first == "#2")
        #expect(ir.second == "#3")
        #expect(ir.friendlyInput == "gcd #2, #3")
    }

    @Test func rejectsNonBinary() {
        #expect(BinaryFormulaIR.parse("factor x^2") == nil)
        #expect(BinaryFormulaIR.parse("gcd(12, 18)") == nil)
    }
}

@Suite("Number-theory unary kinds ride UnaryFormulaIR")
struct BatchFUnaryIRTests {
    @Test func parsesFactorial() {
        guard let ir = UnaryFormulaIR.parse("factorial 5") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.keyword == .factorial)
        #expect(ir.expression == "5")
        #expect(ir.friendlyInput == "factorial 5")
    }

    @Test func parsesIsPrime() {
        guard let ir = UnaryFormulaIR.parse("is_prime 104729") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.keyword == .isPrime)
        #expect(ir.friendlyInput == "is_prime 104729")
    }

    @Test func parsesFactorInteger() {
        guard let ir = UnaryFormulaIR.parse("factor_integer 3600") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.keyword == .factorInteger)
        #expect(ir.friendlyInput == "factor_integer 3600")
    }

    // The alias renders the canonical command.
    @Test func primeFactorizationAliasCanonicalizes() {
        guard let ir = UnaryFormulaIR.parse("prime_factorization 60") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.keyword == .factorInteger)
        #expect(ir.friendlyInput == "factor_integer 60")
    }

    @Test func parsesMean() {
        guard let ir = UnaryFormulaIR.parse("mean [1, 2, 3]") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.keyword == .mean)
        #expect(ir.expression == "[1, 2, 3]")
        #expect(ir.friendlyInput == "mean [1, 2, 3]")
    }

    @Test func roundTripStability() {
        guard var ir = UnaryFormulaIR.parse("factorial 5") else {
            Issue.record("expected parse"); return
        }
        ir.expression = "n + 1"
        let rendered = ir.friendlyInput
        #expect(rendered == "factorial n + 1")
        #expect(UnaryFormulaIR.parse(rendered) == ir)
    }

    // #ROW preservation.
    @Test func preservesRowReference() {
        guard let mean = UnaryFormulaIR.parse("mean #4") else {
            Issue.record("expected parse"); return
        }
        #expect(mean.expression == "#4")
        #expect(mean.friendlyInput == "mean #4")

        guard let fact = UnaryFormulaIR.parse("factorial #2") else {
            Issue.record("expected parse"); return
        }
        #expect(fact.expression == "#2")
        #expect(fact.friendlyInput == "factorial #2")
    }
}

@Suite("FormulaIR dispatch (Batch F)")
struct FormulaIRDispatchBatchFTests {
    @Test func dispatchesVar() {
        guard case .varDeclaration = FormulaIR.parse("var x y") else {
            Issue.record("expected .varDeclaration"); return
        }
        guard case .varDeclaration = FormulaIR.parse("var") else {
            Issue.record("expected .varDeclaration for bare var"); return
        }
    }

    // `var = 3` is an assignment; no formula bar should claim it.
    @Test func varAssignmentDoesNotDispatch() {
        #expect(FormulaIR.parse("var = 3") == nil)
    }

    @Test func dispatchesAssume() {
        guard case .assume = FormulaIR.parse("assume x > 0") else {
            Issue.record("expected .assume"); return
        }
    }

    @Test func dispatchesBinary() {
        for trigger in ["choose 10, 3", "gcd 12, 18", "lcm [1, 2]"] {
            guard case .binary = FormulaIR.parse(trigger) else {
                Issue.record("expected .binary for \(trigger)"); continue
            }
        }
    }

    @Test func dispatchesNumberTheoryUnary() {
        for (trigger, kind) in [
            ("factorial 5", UnaryFormulaIR.Kind.factorial),
            ("is_prime 7", .isPrime),
            ("factor_integer 60", .factorInteger),
            ("prime_factorization 60", .factorInteger),
            ("mean [1, 2, 3]", .mean),
        ] {
            guard case let .unary(ir) = FormulaIR.parse(trigger), ir.keyword == kind else {
                Issue.record("expected .unary(\(kind)) for \(trigger)"); continue
            }
        }
    }
}
