import Testing

@testable import NotchPilotCore

@Test func version() { #expect(Version.current == "0.1.0") }
