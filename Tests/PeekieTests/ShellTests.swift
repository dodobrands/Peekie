import Foundation
import Testing
@testable import PeekieSDK

struct ShellTests {
    @Test
    func test() async throws {
        let data = try await Shell.execute("which", arguments: ["swift"])
        let result =
            String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(result == "/usr/bin/swift")
    }
}
