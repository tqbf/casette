import Testing
@testable import SageDoctor

@Suite("SageVersion — parsing and policy")
struct SageVersionTests {
  @Test("parses the real Sage 9.5 banner")
  func parsesRealBanner() {
    let version = SageVersion.parse("SageMath version 9.5, Release Date: 2022-01-30")
    #expect(version?.major == 9)
    #expect(version?.minor == 5)
  }

  @Test("parses a two-digit major")
  func parsesTenDotThree() {
    let version = SageVersion.parse("SageMath version 10.3, Release Date: 2024-03-19")
    #expect(version?.major == 10)
    #expect(version?.minor == 3)
  }

  @Test("returns nil on a banner with no version number")
  func nilOnNoNumber() {
    #expect(SageVersion.parse("not a version string") == nil)
  }

  @Test("comparison is by major then minor")
  func comparison() {
    let v95 = SageVersion(major: 9, minor: 5, raw: "")
    let v92 = SageVersion(major: 9, minor: 2, raw: "")
    let v103 = SageVersion(major: 10, minor: 3, raw: "")
    #expect(v92 < v95)
    #expect(v95 < v103)
    #expect(v95 >= SageVersionPolicy.floor)
  }

  @Test("9.5 is supported (at the floor)")
  func floorIsSupported() {
    let version = SageVersion(major: 9, minor: 5, raw: "")
    #expect(SageVersionPolicy.standing(for: version) == .supported)
  }

  @Test("10.x is supported (above floor)")
  func aboveFloorSupported() {
    let version = SageVersion(major: 10, minor: 0, raw: "")
    #expect(SageVersionPolicy.standing(for: version) == .supported)
  }

  @Test("9.2 is below the floor (warning band)")
  func belowFloorWarns() {
    let version = SageVersion(major: 9, minor: 2, raw: "")
    #expect(SageVersionPolicy.standing(for: version) == .belowFloor)
  }

  @Test("nil version is unknown")
  func nilIsUnknown() {
    #expect(SageVersionPolicy.standing(for: nil) == .unknown)
  }
}
