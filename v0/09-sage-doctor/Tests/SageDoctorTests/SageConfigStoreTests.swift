import Foundation
import Testing
@testable import SageDoctor

@Suite("SageConfigStore — store / load / forget (hermetic)")
struct SageConfigStoreTests {
  /// A store rooted at a fresh temp dir via the env-override mechanism, so it
  /// never touches the real Application Support file.
  private func makeTempStore() -> (store: SageConfigStore, dir: URL) {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("casette-doctor-test-\(UUID().uuidString)", isDirectory: true)
    let store = SageConfigStore(
      environment: [SageConfigStore.directoryOverrideKey: dir.path])
    return (store, dir)
  }

  @Test("absent file loads as empty config")
  func emptyWhenAbsent() {
    let (store, _) = makeTempStore()
    #expect(store.storedPath() == nil)
  }

  @Test("store then load round-trips the path")
  func storeRoundTrips() throws {
    let (store, dir) = makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    try store.store(sagePath: "/opt/homebrew/bin/sage")
    #expect(store.storedPath() == "/opt/homebrew/bin/sage")
    // A fresh store object pointed at the same dir reads the same value.
    let reopened = SageConfigStore(
      environment: [SageConfigStore.directoryOverrideKey: dir.path])
    #expect(reopened.storedPath() == "/opt/homebrew/bin/sage")
  }

  @Test("store overwrites a prior path")
  func storeOverwrites() throws {
    let (store, dir) = makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    try store.store(sagePath: "/first/sage")
    try store.store(sagePath: "/second/sage")
    #expect(store.storedPath() == "/second/sage")
  }

  @Test("forget clears the stored path")
  func forgetClears() throws {
    let (store, dir) = makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    try store.store(sagePath: "/opt/homebrew/bin/sage")
    try store.forget()
    #expect(store.storedPath() == nil)
  }

  @Test("forget on an absent file is a no-op, not an error")
  func forgetIdempotent() throws {
    let (store, _) = makeTempStore()
    try store.forget()  // must not throw
    #expect(store.storedPath() == nil)
  }

  @Test("a corrupt config file degrades to empty, not a crash")
  func corruptDegrades() throws {
    let (store, dir) = makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: store.fileURL)
    #expect(store.storedPath() == nil)
  }

  @Test("the real (non-override) location is under Application Support/Casette")
  func realLocationIsApplicationSupport() {
    let store = SageConfigStore(environment: [:])
    #expect(store.fileURL.path.contains("Application Support/Casette"))
    #expect(store.fileURL.lastPathComponent == "sage-doctor.json")
  }
}
