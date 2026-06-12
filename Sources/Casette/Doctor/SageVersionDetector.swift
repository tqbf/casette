import Foundation

/// The outcome of probing a binary with `--version`: the raw banner line, the
/// parsed `major.minor` (nil when unparseable), and a one-line detail used as
/// the actionable failure message when nothing parsed.
struct SageVersionDetection: Sendable {
    let raw: String?
    let parsed: SageVersion?
    let detail: String

    /// The version string the UI / session header shows: parsed `major.minor`
    /// when available, else the raw banner, else nil.
    var displayVersion: String? {
        parsed.map { "\($0.major).\($0.minor)" } ?? raw
    }
}

/// Runs `<sage> --version` and parses the banner — the async in-app port of
/// v0/09 `SageDoctor.detectVersion` (same bounded-call policy: a hung
/// `--version` can't wedge the caller; same tolerant `MAJOR.MINOR` parse).
/// Used by the Doctor's version check AND by the session-header `sageVersion`
/// fill after the kernel boots.
enum SageVersionDetector {
    static func detect(
        sagePath: String,
        timeout: Duration = .seconds(60)
    ) async -> SageVersionDetection {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sagePath)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return SageVersionDetection(
                raw: nil, parsed: nil,
                detail: "could not run `\(sagePath) --version`: \(error.localizedDescription)")
        }
        // Bound the call so a hung "sage --version" can't wedge the doctor.
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while process.isRunning, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if process.isRunning {
            process.terminate()
            return SageVersionDetection(
                raw: nil, parsed: nil,
                detail: "`\(sagePath) --version` did not return within \(timeout) (is this Sage?)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            return SageVersionDetection(
                raw: nil, parsed: nil,
                detail: "`\(sagePath) --version` produced no output (not a Sage binary?)")
        }
        let parsed = SageVersion.parse(output)
        return SageVersionDetection(
            raw: output, parsed: parsed,
            detail: parsed == nil ? "no MAJOR.MINOR found in: \(output)" : output)
    }
}
