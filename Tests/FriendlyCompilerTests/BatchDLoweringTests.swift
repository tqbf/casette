import Testing
@testable import FriendlyCompiler

// Batch D lowerings: the new linear-algebra keyword forms — `vector`, `det`,
// `inverse`, `transpose`, `rank`, `eigenvectors` — plus the variable-payload
// extension of the matrix-method path (which the existing `eigenvalues`/`rref`
// keywords now also route through). The frozen V0.7 literal-payload assertions
// stay byte-identical; these assertions are additive.

private func expectSuccess(_ input: String, _ expectedSage: String,
                           sourceLocation: SourceLocation = #_sourceLocation) {
    let r = FriendlyCompiler.compile(input)
    guard case let .success(s, _) = r else {
        Issue.record("expected .success for \(input), got \(r)", sourceLocation: sourceLocation)
        return
    }
    #expect(s == expectedSage, sourceLocation: sourceLocation)
}

private func requiredVars(_ input: String,
                          sourceLocation: SourceLocation = #_sourceLocation) -> [String]? {
    let r = FriendlyCompiler.compile(input)
    guard case let .success(_, vars) = r else {
        Issue.record("expected .success for \(input), got \(r)", sourceLocation: sourceLocation)
        return nil
    }
    return vars
}

private func expectError(_ input: String,
                         sourceLocation: SourceLocation = #_sourceLocation) -> CompileError? {
    let r = FriendlyCompiler.compile(input)
    guard case let .error(e) = r else {
        Issue.record("expected .error for \(input), got \(r)", sourceLocation: sourceLocation)
        return nil
    }
    return e
}

private func expectBypass(_ input: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let r = FriendlyCompiler.compile(input)
    guard case .bypass = r else {
        Issue.record("expected .bypass for \(input), got \(r)", sourceLocation: sourceLocation)
        return
    }
}

@Suite("Matrix-method lowering (Batch D)")
struct MatrixMethodLowering {
    // MARK: det

    @Test func detLiteralMatlab() {
        expectSuccess("det [1,2; 3,4]", "matrix([[1,2],[3,4]]).det()")
    }

    @Test func detLiteralRowList() {
        expectSuccess("det [[1,2],[3,4]]", "matrix([[1,2],[3,4]]).det()")
    }

    @Test func detVariable() {
        expectSuccess("det A", "(A).det()")
        #expect(requiredVars("det A") == ["A"])
    }

    @Test func detExpression() {
        expectSuccess("det A*B", "(A*B).det()")
        #expect(requiredVars("det A*B") == ["A", "B"])
    }

    @Test func determinantAlias() {
        expectSuccess("determinant [1,2; 3,4]", "matrix([[1,2],[3,4]]).det()")
        expectSuccess("determinant A", "(A).det()")
    }

    @Test func detCallSyntaxBypasses() {
        // `det(A)` has no whitespace after `det`, so it is not the command.
        expectBypass("det(A)")
    }

    // MARK: inverse / transpose / rank

    @Test func inverseLiteralAndVariable() {
        expectSuccess("inverse [1,2; 3,4]", "matrix([[1,2],[3,4]]).inverse()")
        expectSuccess("inverse A", "(A).inverse()")
    }

    @Test func transposeLiteralAndVariable() {
        expectSuccess("transpose [1,2; 3,4]", "matrix([[1,2],[3,4]]).transpose()")
        expectSuccess("transpose A", "(A).transpose()")
    }

    @Test func rankLiteralAndVariable() {
        expectSuccess("rank [1,2; 3,4]", "matrix([[1,2],[3,4]]).rank()")
        expectSuccess("rank A", "(A).rank()")
    }

    // MARK: eigenvectors (lowering chosen: right eigenvectors)

    @Test func eigenvectorsLiteral() {
        expectSuccess("eigenvectors [1,2; 3,4]", "matrix([[1,2],[3,4]]).eigenvectors_right()")
    }

    @Test func eigenvectorsVariable() {
        expectSuccess("eigenvectors A", "(A).eigenvectors_right()")
        #expect(requiredVars("eigenvectors A") == ["A"])
    }

    @Test func eigenvectorAlias() {
        expectSuccess("eigenvector [1,2; 3,4]", "matrix([[1,2],[3,4]]).eigenvectors_right()")
    }

    // MARK: the existing keywords now also accept variable payloads

    @Test func eigenvaluesVariablePayload() {
        expectSuccess("eigenvalues A", "(A).eigenvalues()")
        #expect(requiredVars("eigenvalues A") == ["A"])
    }

    @Test func rrefVariablePayload() {
        expectSuccess("rref A", "(A).rref()")
        #expect(requiredVars("rref A") == ["A"])
    }

    // MARK: tape references (expanded by CompiledInput before reaching us)

    @Test func detExpandedTapeReferenceTakesValuePath() {
        // A `#3` reference reaches the compiler already expanded to an
        // identifier-shaped `__casette_tape_refs[3]`; it must NOT be treated as
        // a bracketed literal even though it contains `[`.
        expectSuccess(
            "det __casette_tape_refs[3]",
            "(__casette_tape_refs[3]).det()")
    }

    // MARK: empty payloads error with example usage

    @Test func detEmptyErrors() {
        let e = expectError("det")
        #expect(e?.suggestion?.contains("det") == true)
    }

    @Test func eigenvectorsEmptyErrors() {
        let e = expectError("eigenvectors")
        #expect(e?.suggestion?.contains("eigenvectors") == true)
    }
}

@Suite("Vector lowering (Batch D)")
struct VectorLowering {
    @Test func happyPath() {
        expectSuccess("vector [1,2,3]", "vector([1,2,3])")
    }

    @Test func passesEntriesVerbatim() {
        // No row normalization: a flat list passes through unchanged.
        expectSuccess("vector [a, b, c]", "vector([a, b, c])")
        #expect(requiredVars("vector [a, b, c]") == ["a", "b", "c"])
    }

    @Test func nonBracketedErrors() {
        let e = expectError("vector 1, 2, 3")
        #expect(e?.suggestion?.contains("vector") == true)
    }

    @Test func emptyErrors() {
        let e = expectError("vector")
        #expect(e?.suggestion?.contains("vector") == true)
    }

    @Test func callSyntaxBypasses() {
        expectBypass("vector(1,2,3)")
    }
}
