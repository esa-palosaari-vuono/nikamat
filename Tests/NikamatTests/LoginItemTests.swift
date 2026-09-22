import Foundation
import Testing
@testable import Nikamat

@MainActor
struct LoginItemTests {
    /// Characters that would break a hand-written XML template.
    @Test func awkwardApplicationPathsSurviveSerialisation() throws {
        let path = "/Users/a & b/<Apps>/Nikamat \"beta\".app"
        let data = try LoginItem.agentPlist(label: "fi.example.nikamat", appPath: path)
        let agent = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(agent["Label"] as? String == "fi.example.nikamat")
        #expect(agent["ProgramArguments"] as? [String] == ["/usr/bin/open", "-a", path])
        #expect(agent["RunAtLoad"] as? Bool == true)
    }
}
