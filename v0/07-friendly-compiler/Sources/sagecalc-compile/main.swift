// sagecalc-compile — thin CLI wrapper around FriendlyCompiler.
//
//   sagecalc-compile "double integral x*y, x=0..1, y=0..x"
//     -> prints the generated Sage
//   sagecalc-compile --json "..."
//     -> prints a JSON object for tooling (the e2e driver / V1.4 dev tools)
//
// Exit codes: 0 success/bypass, 2 error, 3 ambiguous, 64 usage. The library does
// all the work; this file is just argument plumbing + formatting.

import FriendlyCompiler
import Foundation

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: sagecalc-compile [--json] "<input>"

      Compiles forgiving command-shim input into Sage source.
      --json   emit a structured JSON result instead of plain text.

    examples:
      sagecalc-compile "factor x^4 - 1"
      sagecalc-compile "double integral x*y, x=0..1, y=0..x"
      sagecalc-compile --json "integral x^2, x=0..1"

    """.utf8))
    exit(64)
}

var args = Array(CommandLine.arguments.dropFirst())
var json = false
if let idx = args.firstIndex(of: "--json") {
    json = true
    args.remove(at: idx)
}
guard args.count == 1 else { usage() }
let input = args[0]

let result = FriendlyCompiler.compile(input)

func emitJSON(_ obj: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

switch result {
case let .success(sage, vars):
    if json {
        emitJSON(["status": "success", "sage": sage, "requiredVariables": vars, "input": input])
    } else {
        print(sage)
    }
    exit(0)

case let .bypass(sage):
    if json {
        emitJSON(["status": "bypass", "sage": sage, "requiredVariables": [], "input": input])
    } else {
        print(sage)
    }
    exit(0)

case let .error(err):
    if json {
        var obj: [String: Any] = ["status": "error", "message": err.message, "input": input]
        if let p = err.position { obj["position"] = p }
        if let s = err.suggestion { obj["suggestion"] = s }
        emitJSON(obj)
    } else {
        var line = "error: \(err.message)"
        if let s = err.suggestion { line += "\n       \(s)" }
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
    exit(2)

case let .ambiguous(candidates):
    if json {
        emitJSON(["status": "ambiguous", "candidates": candidates, "input": input])
    } else {
        FileHandle.standardError.write(Data("ambiguous — candidates:\n".utf8))
        for c in candidates {
            FileHandle.standardError.write(Data("  \(c)\n".utf8))
        }
    }
    exit(3)
}
