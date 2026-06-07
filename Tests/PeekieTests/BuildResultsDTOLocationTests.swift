import Foundation
import Testing
@testable import PeekieSDK

struct BuildResultsDTOLocationTests {
    // MARK: Internal

    @Test
    func fullFragmentParsesAllFourFields() {
        let url =
            "file:///Users/foo/foo.swift#EndingColumnNumber=8&EndingLineNumber=4&"
                + "StartingColumnNumber=4&StartingLineNumber=3&Timestamp=802245068.4496371"
        let loc = issue(sourceURL: url).location
        #expect(loc == .init(startLine: 3, startColumn: 4, endLine: 4, endColumn: 8))
    }

    @Test
    func onlyStartingLinePopulatesStartLineAndNilsTheRest() {
        let url = "file:///Users/foo/foo.swift#StartingLineNumber=12"
        let loc = issue(sourceURL: url).location
        #expect(loc == .init(startLine: 12, startColumn: nil, endLine: nil, endColumn: nil))
    }

    @Test
    func nilSourceURLProducesNilLocation() {
        #expect(issue(sourceURL: nil).location == nil)
    }

    @Test
    func sourceURLWithoutFragmentProducesNilLocation() {
        #expect(issue(sourceURL: "file:///Users/foo/foo.swift").location == nil)
    }

    @Test
    func fragmentWithoutStartingLineProducesNilLocation() {
        let url = "file:///Users/foo/foo.swift#EndingLineNumber=4&StartingColumnNumber=2"
        #expect(issue(sourceURL: url).location == nil)
    }

    @Test
    func malformedFragmentParsesGracefully() {
        let url = "file:///Users/foo/foo.swift#garbage&no=equals=here&StartingLineNumber=7"
        let loc = issue(sourceURL: url).location
        #expect(loc?.startLine == 7)
    }

    // MARK: Private

    private func issue(sourceURL: String?) -> BuildResultsDTO.Issue {
        BuildResultsDTO.Issue(
            issueType: "Swift Compiler Warning", message: "m", sourceURL: sourceURL
        )
    }
}
