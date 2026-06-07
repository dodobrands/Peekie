import Foundation
import Testing
@testable import PeekieSDK

struct ParseErrorsTests {
    @Test
    func errorsArrayDecodesSymmetricallyToWarnings() throws {
        let json = """
        {
            "warningCount": 1,
            "errorCount": 1,
            "warnings": [
                { "issueType": "DeprecatedDeclaration", "message": "warned",
                  "sourceURL": "file:///foo.swift#StartingLineNumber=1" }
            ],
            "errors": [
                { "issueType": "Swift Compiler Error", "message": "expected expression",
                  "sourceURL": "file:///foo.swift#StartingLineNumber=42" }
            ]
        }
        """
        let dto = try JSONDecoder().decode(BuildResultsDTO.self, from: Data(json.utf8))

        #expect(dto.warnings.count == 1)
        #expect(dto.errors.count == 1)
        #expect(dto.errors.first?.issueType == "Swift Compiler Error")
    }

    @Test
    func errorsArrayDefaultsToEmptyWhenAbsent() throws {
        let json = """
        { "warningCount": 0, "warnings": [] }
        """
        let dto = try JSONDecoder().decode(BuildResultsDTO.self, from: Data(json.utf8))

        #expect(dto.warnings.isEmpty)
        #expect(dto.errors.isEmpty)
    }

    @Test
    func parseErrorsGroupsByFileNameAndPreservesLocation() async {
        let dto = BuildResultsDTO(
            warnings: [],
            errors: [
                .init(
                    issueType: "Swift Compiler Error",
                    message: "cannot find 'foo' in scope",
                    sourceURL: "file:///Calculator.swift#StartingLineNumber=10"
                ),
                .init(
                    issueType: "Swift Compiler Error",
                    message: "another error",
                    sourceURL: "file:///Calculator.swift#StartingLineNumber=12"
                ),
            ]
        )

        let result = await Report.parseErrors(from: dto)
        let issues = try? #require(result["Calculator.swift"])
        #expect(issues?.count == 2)
        #expect(issues?.compactMap { $0.location?.startLine }.sorted() == [10, 12])
        #expect(
            issues?.allSatisfy {
                $0.type == .swiftCompilerError
            } == true
        )
    }

    @Test
    func parseErrorsDropsRecordsWithoutSourceURL() async {
        let dto = BuildResultsDTO(
            warnings: [],
            errors: [
                .init(
                    issueType: "Swift Compiler Error",
                    message: "linker error",
                    sourceURL: nil
                ),
            ]
        )

        let result = await Report.parseErrors(from: dto)
        #expect(result.isEmpty)
    }
}
