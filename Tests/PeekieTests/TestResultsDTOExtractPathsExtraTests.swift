import Foundation
import Testing
@testable import PeekieSDK

struct TestResultsDTOExtractPathsExtraTests {
    @Test
    func extractPathsIgnoresMetadataNodes() {
        // Test Case -> Device -> Failure Message -> Repetition
        let failureMessage = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: nil,
            name: "Test failed",
            nodeIdentifierURL: nil,
            nodeType: .failureMessage,
            result: nil
        )

        let repetition = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.1,
            name: "First Run",
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .failed
        )

        let device = TestResultsDTO.TestNode(
            children: [failureMessage, repetition],
            durationInSeconds: nil,
            name: "iPhone 13",
            nodeIdentifierURL: nil,
            nodeType: .device,
            result: nil
        )

        let paths = TestResultsDTO.extractPaths(from: [device])

        #expect(
            paths == [
                [
                    Report.Module.Suite.RepeatableTest.PathNode(name: "iPhone 13", type: .device),
                    Report.Module.Suite.RepeatableTest.PathNode(
                        name: "First Run", type: .repetition
                    ),
                ],
            ]
        )
    }

    @Test
    func extractPathsFromEmptyChildren() {
        let paths = TestResultsDTO.extractPaths(from: [])
        #expect(paths.isEmpty)
    }

    @Test
    func extractPathsFromComplexNestedStructure() {
        // Test Case -> Device -> Arguments (false) -> Repetition (First Run, Retry 1)
        //              Device -> Arguments (true) -> Repetition (First Run)
        let repetition1 = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.0,
            name: "First Run",
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .failed
        )

        let repetition2 = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.0,
            name: "Retry 1",
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .failed
        )

        let argumentsFalse = TestResultsDTO.TestNode(
            children: [repetition1, repetition2],
            durationInSeconds: nil,
            name: "false",
            nodeIdentifierURL: nil,
            nodeType: .arguments,
            result: nil
        )

        let repetition3 = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.0,
            name: "First Run",
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .passed
        )

        let argumentsTrue = TestResultsDTO.TestNode(
            children: [repetition3],
            durationInSeconds: nil,
            name: "true",
            nodeIdentifierURL: nil,
            nodeType: .arguments,
            result: nil
        )

        let device = TestResultsDTO.TestNode(
            children: [argumentsFalse, argumentsTrue],
            durationInSeconds: nil,
            name: "iPhone 13",
            nodeIdentifierURL: nil,
            nodeType: .device,
            result: nil
        )

        let paths = TestResultsDTO.extractPaths(from: [device])

        #expect(
            paths == [
                [
                    Report.Module.Suite.RepeatableTest.PathNode(name: "iPhone 13", type: .device),
                    Report.Module.Suite.RepeatableTest.PathNode(name: "false", type: .arguments),
                    Report.Module.Suite.RepeatableTest.PathNode(
                        name: "First Run", type: .repetition
                    ),
                ],
                [
                    Report.Module.Suite.RepeatableTest.PathNode(name: "iPhone 13", type: .device),
                    Report.Module.Suite.RepeatableTest.PathNode(name: "false", type: .arguments),
                    Report.Module.Suite.RepeatableTest.PathNode(name: "Retry 1", type: .repetition),
                ],
                [
                    Report.Module.Suite.RepeatableTest.PathNode(name: "iPhone 13", type: .device),
                    Report.Module.Suite.RepeatableTest.PathNode(name: "true", type: .arguments),
                    Report.Module.Suite.RepeatableTest.PathNode(
                        name: "First Run", type: .repetition
                    ),
                ],
            ]
        )
    }
}
