import Foundation
import Testing
@testable import PeekieSDK

struct ShellTests {
    @Test
    func test() async throws {
        let result = try await Shell.execute("which", arguments: ["swift"])
        #expect(result == "/usr/bin/swift")
    }
}
