import Foundation
import Testing
@testable import PeekieSDK

struct ParseWarningsDedupTests {
    @Test
    func identicalMessagesInSameFileAreNotDeduplicated() async {
        let dto = BuildResultsDTO(warnings: [
            .init(
                issueType: "DeprecatedDeclaration",
                message: "'oldFoo()' is deprecated: use bar",
                sourceURL: "file:///foo.swift#StartingLineNumber=4"
            ),
            .init(
                issueType: "DeprecatedDeclaration",
                message: "'oldFoo()' is deprecated: use bar",
                sourceURL: "file:///foo.swift#StartingLineNumber=5"
            ),
            .init(
                issueType: "DeprecatedDeclaration",
                message: "'oldFoo()' is deprecated: use bar",
                sourceURL: "file:///foo.swift#StartingLineNumber=12"
            ),
        ])

        let result = await Report.parseWarnings(from: dto)

        let issues = try? #require(result["foo.swift"])
        #expect(issues?.count == 3)
        #expect(issues?.compactMap { $0.location?.startLine }.sorted() == [4, 5, 12])
    }
}
