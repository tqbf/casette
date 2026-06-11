import Foundation
import SageDoctor

// sage-doctor — the V0.9 CLI that drives the SageDoctor library.
//
// Usage:
//   sage-doctor                 run the full diagnostic (human report)
//   sage-doctor --json          emit the JSON report (the V1.10 contract)
//   sage-doctor --sage PATH     override discovery: test this binary
//   sage-doctor --use PATH      store PATH as the selected Sage, then run
//   sage-doctor --forget        clear the stored Sage path
//   sage-doctor --where         print the resolved worker.py + config file paths
//
// Exit code: 0 if a Sage was found and all checks passed, 1 otherwise.

struct Options {
  var json = false
  var sageOverride: String?
  var use: String?
  var forget = false
  var showWhere = false
}

func parseOptions(_ arguments: [String]) -> Options {
  var options = Options()
  var index = 0
  while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--json":
      options.json = true
    case "--sage":
      index += 1
      options.sageOverride = index < arguments.count ? arguments[index] : nil
    case "--use":
      index += 1
      options.use = index < arguments.count ? arguments[index] : nil
    case "--forget":
      options.forget = true
    case "--where":
      options.showWhere = true
    default:
      FileHandle.standardError.write(Data("warning: ignoring unknown argument \(argument)\n".utf8))
    }
    index += 1
  }
  return options
}

func printErr(_ message: String) {
  FileHandle.standardError.write(Data((message + "\n").utf8))
}

let options = parseOptions(Array(CommandLine.arguments.dropFirst()))
let configStore = SageConfigStore()

if options.showWhere {
  print("worker.py: \(SageDoctor.defaultWorkerPath())")
  print("config file: \(configStore.fileURL.path)")
  exit(0)
}

if options.forget {
  do {
    try configStore.forget()
    print("Forgot stored Sage path (\(configStore.fileURL.path)).")
  } catch {
    printErr("error: could not clear config: \(error)")
    exit(1)
  }
  exit(0)
}

// `--use PATH` stores the path before running so subsequent runs prefer it.
if let use = options.use {
  do {
    try configStore.store(sagePath: use)
    print("Stored Sage path: \(use)")
  } catch {
    printErr("error: could not store config: \(error)")
    exit(1)
  }
}

let storedPath = configStore.storedPath()
let doctor = SageDoctor()
let report = doctor.run(override: options.sageOverride, storedPath: storedPath)

if options.json {
  do {
    print(try ReportFormatter.json(report))
  } catch {
    printErr("error: could not encode JSON report: \(error)")
    exit(1)
  }
} else {
  print(ReportFormatter.humanReadable(report))
}

exit(report.overallOK ? 0 : 1)
