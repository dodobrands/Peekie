import Foundation
import Testing
@testable import PeekieSDK

/// Apple's xcresulttool emits a single Swift `#warning("…")` directive as two
/// records in the `warnings[]` bucket: one with `issueType: "Swift Compiler
/// Error"` and one with `"Swift Compiler Warning"`. Both records share the
/// same `sourceURL` (full Location) and, after `normalizeWarningMessage`,
/// the same `message`. We collapse such twins into a single record whose
/// `IssueType` matches the bucket severity.
///
/// Asymmetric to ``ParseWarningsDedupTests`` (which guards #174): that test
/// fixed dedup on `message` alone — distinct lines lost data. Our key
/// includes the full Location, so #174's scenario is preserved.
struct ParseIssuesTwinDedupTests {
    @Test
    func warningBucketTwinCollapsesToSwiftCompilerWarning() async {
        let dto = BuildResultsDTO(warnings: [
            .init(
                issueType: "Swift Compiler Error",
                message: """
                Some warning from Calculator
                        #warning("Some warning from Calculator")
                         ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
                """,
                sourceURL: "file:///Calculator.swift#EndingColumnNumber=17&EndingLineNumber=7&StartingColumnNumber=17&StartingLineNumber=7"
            ),
            .init(
                issueType: "Swift Compiler Warning",
                message: "Some warning from Calculator",
                sourceURL: "file:///Calculator.swift#EndingColumnNumber=17&EndingLineNumber=7&StartingColumnNumber=17&StartingLineNumber=7"
            ),
        ])

        let result = await Report.parseWarnings(from: dto)
        let issues = try? #require(result["Calculator.swift"])
        #expect(issues?.count == 1)
        #expect(issues?.first?.type == .swiftCompilerWarning)
        #expect(issues?.first?.message == "Some warning from Calculator")
    }

    @Test
    func errorBucketTwinCollapsesToSwiftCompilerError() async {
        let dto = BuildResultsDTO(errors: [
            .init(
                issueType: "Swift Compiler Warning",
                message: "Boom",
                sourceURL: "file:///Boom.swift#EndingColumnNumber=9&EndingLineNumber=42&StartingColumnNumber=9&StartingLineNumber=42"
            ),
            .init(
                issueType: "Swift Compiler Error",
                message: "Boom",
                sourceURL: "file:///Boom.swift#EndingColumnNumber=9&EndingLineNumber=42&StartingColumnNumber=9&StartingLineNumber=42"
            ),
        ])

        let result = await Report.parseErrors(from: dto)
        let issues = try? #require(result["Boom.swift"])
        #expect(issues?.count == 1)
        #expect(issues?.first?.type == .swiftCompilerError)
    }

    @Test
    func sameMessageOnDifferentLinesIsPreserved() async {
        // Guards #174: distinct startLine → distinct TwinKey → no collapse.
        let dto = BuildResultsDTO(warnings: [
            .init(
                issueType: "DeprecatedDeclaration",
                message: "'oldFoo()' is deprecated: use bar",
                sourceURL: "file:///Foo.swift#StartingLineNumber=4"
            ),
            .init(
                issueType: "DeprecatedDeclaration",
                message: "'oldFoo()' is deprecated: use bar",
                sourceURL: "file:///Foo.swift#StartingLineNumber=5"
            ),
            .init(
                issueType: "DeprecatedDeclaration",
                message: "'oldFoo()' is deprecated: use bar",
                sourceURL: "file:///Foo.swift#StartingLineNumber=12"
            ),
        ])

        let result = await Report.parseWarnings(from: dto)
        let issues = try? #require(result["Foo.swift"])
        #expect(issues?.count == 3)
        #expect(issues?.compactMap { $0.location?.startLine }.sorted() == [4, 5, 12])
    }

    @Test
    func twinWithMismatchingEndColumnIsNotCollapsed() async {
        // Distinct endColumn → distinct TwinKey → both kept. Documents
        // the strictness of our key: any of the four coordinates differing
        // is enough to disqualify dedup.
        let dto = BuildResultsDTO(warnings: [
            .init(
                issueType: "Swift Compiler Error",
                message: "x",
                sourceURL: "file:///A.swift#EndingColumnNumber=10&EndingLineNumber=1&StartingColumnNumber=1&StartingLineNumber=1"
            ),
            .init(
                issueType: "Swift Compiler Warning",
                message: "x",
                sourceURL: "file:///A.swift#EndingColumnNumber=20&EndingLineNumber=1&StartingColumnNumber=1&StartingLineNumber=1"
            ),
        ])

        let result = await Report.parseWarnings(from: dto)
        let issues = try? #require(result["A.swift"])
        #expect(issues?.count == 2)
    }

    @Test
    func issuesWithNilLocationArePassedThrough() async {
        // Without a Location we have no spatial proof two records are the
        // same diagnostic; pass through.
        let dto = BuildResultsDTO(warnings: [
            .init(
                issueType: "Swift Compiler Warning",
                message: "general",
                sourceURL: "file:///Z.swift"
            ),
            .init(
                issueType: "Swift Compiler Error",
                message: "general",
                sourceURL: "file:///Z.swift"
            ),
        ])

        let result = await Report.parseWarnings(from: dto)
        let issues = try? #require(result["Z.swift"])
        #expect(issues?.count == 2)
    }
}
