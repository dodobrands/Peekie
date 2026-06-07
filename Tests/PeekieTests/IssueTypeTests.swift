import Foundation
import Testing

@testable import PeekieSDK

private typealias IssueType = Report.File.Issue.IssueType

@Suite
struct IssueTypeTests {
    @Test
    func knownRawValuesMapToTypedCases() {
        #expect(IssueType(rawValue: "Swift Compiler Warning") == .swiftCompilerWarning)
        #expect(IssueType(rawValue: "Swift Compiler Error") == .swiftCompilerError)
        #expect(IssueType(rawValue: "DeprecatedDeclaration") == .deprecatedDeclaration)
        #expect(IssueType(rawValue: "No-usage") == .noUsage)
    }

    @Test
    func unknownRawValueFallsBackToUnknown() {
        #expect(IssueType(rawValue: "FooNewType") == .unknown("FooNewType"))
    }

    @Test
    func rawValueRoundTrips() {
        #expect(IssueType.swiftCompilerWarning.rawValue == "Swift Compiler Warning")
        #expect(IssueType.swiftCompilerError.rawValue == "Swift Compiler Error")
        #expect(IssueType.deprecatedDeclaration.rawValue == "DeprecatedDeclaration")
        #expect(IssueType.noUsage.rawValue == "No-usage")
        #expect(IssueType.unknown("Something").rawValue == "Something")
    }

    @Test
    func codableRoundTripsThroughRawValue() throws {
        let cases: [IssueType] = [
            .swiftCompilerWarning,
            .swiftCompilerError,
            .deprecatedDeclaration,
            .noUsage,
            .unknown("FutureType"),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for value in cases {
            let data = try encoder.encode(value)
            let json = String(data: data, encoding: .utf8)
            #expect(json == "\"\(value.rawValue)\"")

            let decoded = try decoder.decode(IssueType.self, from: data)
            #expect(decoded == value)
        }
    }
}
