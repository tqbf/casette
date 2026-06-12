import Testing
@testable import FriendlyCompiler

// Batch D completion-UI IR: the matrix-shaped family (matrix, vector, det,
// inverse, transpose, rank, rref, eigenvalues, eigenvectors). Like the earlier
// batches, this IR renders back to FRIENDLY INPUT, never Sage, and preserves
// `#ROW` tape references verbatim (docs/COMPLETION-UI.md).

@Suite("Matrix formula IR")
struct MatrixFormulaIRTests {
    @Test func parsesLiteralPayload() {
        guard let ir = MatrixFormulaIR.parse("det [1,2; 3,4]") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.kind == .det)
        #expect(ir.payload == "[1,2; 3,4]")
        #expect(ir.friendlyInput == "det [1,2; 3,4]")
    }

    @Test func parsesVariablePayload() {
        guard let ir = MatrixFormulaIR.parse("inverse A") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.kind == .inverse)
        #expect(ir.payload == "A")
        #expect(ir.friendlyInput == "inverse A")
    }

    @Test func parsesEachKind() {
        let cases: [(String, MatrixFormulaIR.Kind)] = [
            ("matrix [1,2; 3,4]", .matrix),
            ("vector [1,2,3]", .vector),
            ("det A", .det),
            ("inverse A", .inverse),
            ("transpose A", .transpose),
            ("rank A", .rank),
            ("rref A", .rref),
            ("eigenvalues A", .eigenvalues),
            ("eigenvectors A", .eigenvectors),
        ]
        for (input, kind) in cases {
            guard let ir = MatrixFormulaIR.parse(input) else {
                Issue.record("expected parse for \(input)"); continue
            }
            #expect(ir.kind == kind)
        }
    }

    @Test func aliasesNormalizeToCanonicalCommand() {
        // `determinant` / `eigenvector` are aliases; the rendered prefix is the
        // canonical command word.
        guard let det = MatrixFormulaIR.parse("determinant A") else {
            Issue.record("expected parse for determinant"); return
        }
        #expect(det.kind == .det)
        #expect(det.friendlyInput == "det A")

        guard let evec = MatrixFormulaIR.parse("eigenvector A") else {
            Issue.record("expected parse for eigenvector"); return
        }
        #expect(evec.kind == .eigenvectors)
        #expect(evec.friendlyInput == "eigenvectors A")
    }

    @Test func parsesBareCommandWithEmptyPayload() {
        for input in ["det", "matrix", "vector", "eigenvectors", "rank"] {
            guard let ir = MatrixFormulaIR.parse(input) else {
                Issue.record("expected parse for bare \(input)"); continue
            }
            #expect(ir.payload.isEmpty)
            #expect(ir.friendlyInput == input)
        }
    }

    @Test func roundTripStability() {
        guard var ir = MatrixFormulaIR.parse("det [1,2; 3,4]") else {
            Issue.record("expected parse"); return
        }
        ir.payload = "[[1,2],[3,4]]"
        let rendered = ir.friendlyInput
        #expect(rendered == "det [[1,2],[3,4]]")
        #expect(MatrixFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = MatrixFormulaIR.parse("det #3") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.payload == "#3")
        #expect(ir.friendlyInput == "det #3")
        #expect(MatrixFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func rejectsNonMatrixAndCallSyntax() {
        #expect(MatrixFormulaIR.parse("integral x^2") == nil)
        #expect(MatrixFormulaIR.parse("2+2") == nil)
        #expect(MatrixFormulaIR.parse("det(A)") == nil)
    }
}

@Suite("FormulaIR dispatch (Batch D)")
struct FormulaIRDispatchBatchDTests {
    @Test func dispatchesEachTriggerToMatrixOp() {
        let triggers = [
            "matrix [1,2; 3,4]",
            "vector [1,2,3]",
            "det A",
            "determinant A",
            "inverse A",
            "transpose A",
            "rank A",
            "rref A",
            "eigenvalues A",
            "eigenvectors A",
            "eigenvector A",
        ]
        for trigger in triggers {
            guard case .matrixOp = FormulaIR.parse(trigger) else {
                Issue.record("expected .matrixOp for \(trigger)"); continue
            }
        }
    }

    @Test func bareCommandWordsDispatchToMatrixOp() {
        guard case .matrixOp = FormulaIR.parse("det") else {
            Issue.record("expected .matrixOp for bare det"); return
        }
        guard case .matrixOp = FormulaIR.parse("matrix") else {
            Issue.record("expected .matrixOp for bare matrix"); return
        }
    }
}
