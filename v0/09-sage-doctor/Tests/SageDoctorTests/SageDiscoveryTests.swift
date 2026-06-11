import Foundation
import Testing
@testable import SageDoctor

@Suite("SageDiscovery — priority ordering")
struct SageDiscoveryTests {
  /// Builds a discovery with a controllable filesystem and PATH lookup.
  private func makeDiscovery(
    existing: Set<String>,
    onPath: String? = nil,
    bundles: [String] = []
  ) -> SageDiscovery {
    SageDiscovery(
      existenceCheck: { existing.contains($0) },
      pathLookup: { onPath },
      appBundleGlob: { bundles })
  }

  @Test("override beats everything when it exists")
  func overrideWins() {
    let discovery = makeDiscovery(
      existing: ["/custom/sage", "/usr/local/bin/sage"],
      onPath: "/usr/local/bin/sage")
    let result = discovery.discover(override: "/custom/sage", storedPath: "/usr/local/bin/sage")
    #expect(result.selected?.path == "/custom/sage")
    #expect(result.selected?.source == .override)
  }

  @Test("stored path beats known paths and PATH")
  func storedBeatsKnown() {
    let discovery = makeDiscovery(
      existing: ["/opt/homebrew/bin/sage", "/my/stored/sage"],
      onPath: "/opt/homebrew/bin/sage")
    let result = discovery.discover(storedPath: "/my/stored/sage")
    #expect(result.selected?.path == "/my/stored/sage")
    #expect(result.selected?.source == .stored)
  }

  @Test("known paths searched in documented order; homebrew before /usr/local")
  func knownPathOrder() {
    let discovery = makeDiscovery(
      existing: ["/opt/homebrew/bin/sage", "/usr/local/bin/sage"])
    let result = discovery.discover()
    #expect(result.selected?.path == "/opt/homebrew/bin/sage")
    #expect(result.selected?.source == .knownPath)
  }

  @Test("falls through to /usr/local when homebrew absent")
  func fallThroughToUsrLocal() {
    let discovery = makeDiscovery(existing: ["/usr/local/bin/sage"])
    let result = discovery.discover()
    #expect(result.selected?.path == "/usr/local/bin/sage")
  }

  @Test("PATH lookup is last resort")
  func pathLookupLast() {
    let discovery = makeDiscovery(existing: ["/weird/place/sage"], onPath: "/weird/place/sage")
    let result = discovery.discover()
    #expect(result.selected?.path == "/weird/place/sage")
    #expect(result.selected?.source == .pathLookup)
  }

  @Test("app bundle globs are included as known paths")
  func appBundleIncluded() {
    let bundlePath = "/Applications/SageMath-9-5.app/Contents/Resources/sage/sage"
    let discovery = makeDiscovery(existing: [bundlePath], bundles: [bundlePath])
    let result = discovery.discover()
    #expect(result.selected?.path == bundlePath)
  }

  @Test("non-existent candidates are reported but never selected")
  func reportsButSkipsMissing() {
    let discovery = makeDiscovery(existing: [])
    let result = discovery.discover(override: "/nope/sage")
    #expect(result.selected == nil)
    // Override + all known paths are reported even though none exist.
    #expect(result.candidates.contains { $0.path == "/nope/sage" && !$0.exists })
    #expect(result.candidates.count >= SageDiscovery.knownPaths.count)
  }

  @Test("nothing found yields nil selection")
  func nothingFound() {
    let discovery = makeDiscovery(existing: [], onPath: nil)
    let result = discovery.discover()
    #expect(result.selected == nil)
  }

  @Test("duplicate paths are de-duplicated, keeping highest priority source")
  func deduplicates() {
    // /usr/local/bin/sage is both the stored path and a known path; it should
    // appear once, attributed to the higher-priority `stored` source.
    let discovery = makeDiscovery(existing: ["/usr/local/bin/sage"])
    let result = discovery.discover(storedPath: "/usr/local/bin/sage")
    let matches = result.candidates.filter { $0.path == "/usr/local/bin/sage" }
    #expect(matches.count == 1)
    #expect(matches.first?.source == .stored)
  }
}
