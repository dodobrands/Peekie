import Foundation
import Testing

@testable import PeekieSDK

@Suite
struct TestResultsDTOExtractPathsTests {

    @Test
    func extractPathsFromDeviceAndRepetition() throws {
        // Test Case -> Device -> Repetition
        let repetition = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.1,
            name: "First Run",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .passed
        )

        let device = TestResultsDTO.TestNode(
            children: [repetition],
            durationInSeconds: nil,
            name: "iPhone 13",
            nodeIdentifier: nil,
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
                        name: "First Run", type: .repetition),
                ]
            ])
    }

    @Test
    func extractPathsFromMultipleRepetitions() throws {
        // Test Case -> Device -> Repetition (First Run, Retry 1)
        let repetition1 = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.1,
            name: "First Run",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .passed
        )

        let repetition2 = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.05,
            name: "Retry 1",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .passed
        )

        let device = TestResultsDTO.TestNode(
            children: [repetition1, repetition2],
            durationInSeconds: nil,
            name: "iPhone 13",
            nodeIdentifier: nil,
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
                        name: "First Run", type: .repetition),
                ],
                [
                    Report.Module.Suite.RepeatableTest.PathNode(name: "iPhone 13", type: .device),
                    Report.Module.Suite.RepeatableTest.PathNode(name: "Retry 1", type: .repetition),
                ],
            ])
    }

    @Test
    func extractPathsFromArgumentsAndRepetition() throws {
        // Test Case -> Arguments -> Repetition
        let repetition = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.0,
            name: "First Run",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .passed
        )

        let arguments = TestResultsDTO.TestNode(
            children: [repetition],
            durationInSeconds: nil,
            name: "false",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .arguments,
            result: nil
        )

        let paths = TestResultsDTO.extractPaths(from: [arguments])

        #expect(
            paths == [
                [
                    Report.Module.Suite.RepeatableTest.PathNode(name: "false", type: .arguments),
                    Report.Module.Suite.RepeatableTest.PathNode(
                        name: "First Run", type: .repetition),
                ]
            ])
    }

    @Test
    func extractPathsFromDeviceArgumentsAndRepetition() throws {
        // Test Case -> Device -> Arguments -> Repetition
        let repetition = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.0,
            name: "First Run",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .passed
        )

        let arguments = TestResultsDTO.TestNode(
            children: [repetition],
            durationInSeconds: nil,
            name: "false",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .arguments,
            result: nil
        )

        let device = TestResultsDTO.TestNode(
            children: [arguments],
            durationInSeconds: nil,
            name: "iPhone 13",
            nodeIdentifier: nil,
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
                        name: "First Run", type: .repetition),
                ]
            ])
    }

    @Test
    func extractPathsFromArgumentsWithoutRepetition() throws {
        // Test Case -> Device -> Arguments (without Repetition)
        let arguments = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.0,
            name: "false",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .arguments,
            result: .passed
        )

        let device = TestResultsDTO.TestNode(
            children: [arguments],
            durationInSeconds: nil,
            name: "iPhone 13",
            nodeIdentifier: nil,
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
                ]
            ])
    }

    @Test
    func extractPathsFromMultipleArguments() throws {
        // Test Case -> Device -> Arguments (false, true)
        let arguments1 = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.0,
            name: "false",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .arguments,
            result: .passed
        )

        let arguments2 = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.0,
            name: "true",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .arguments,
            result: .passed
        )

        let device = TestResultsDTO.TestNode(
            children: [arguments1, arguments2],
            durationInSeconds: nil,
            name: "iPhone 13",
            nodeIdentifier: nil,
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
                ],
                [
                    Report.Module.Suite.RepeatableTest.PathNode(name: "iPhone 13", type: .device),
                    Report.Module.Suite.RepeatableTest.PathNode(name: "true", type: .arguments),
                ],
            ])
    }

    @Test
    func extractPathsIgnoresMetadataNodes() throws {
        // Test Case -> Device -> Failure Message -> Repetition
        let failureMessage = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: nil,
            name: "Test failed",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .failureMessage,
            result: nil
        )

        let repetition = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.1,
            name: "First Run",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .failed
        )

        let device = TestResultsDTO.TestNode(
            children: [failureMessage, repetition],
            durationInSeconds: nil,
            name: "iPhone 13",
            nodeIdentifier: nil,
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
                        name: "First Run", type: .repetition),
                ]
            ])
    }

    @Test
    func extractPathsFromEmptyChildren() throws {
        let paths = TestResultsDTO.extractPaths(from: [])
        #expect(paths.isEmpty)
    }

    @Test
    func extractPathsFromComplexNestedStructure() throws {
        // Test Case -> Device -> Arguments (false) -> Repetition (First Run, Retry 1)
        //              Device -> Arguments (true) -> Repetition (First Run)
        let repetition1 = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.0,
            name: "First Run",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .failed
        )

        let repetition2 = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.0,
            name: "Retry 1",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .failed
        )

        let argumentsFalse = TestResultsDTO.TestNode(
            children: [repetition1, repetition2],
            durationInSeconds: nil,
            name: "false",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .arguments,
            result: nil
        )

        let repetition3 = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.0,
            name: "First Run",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .repetition,
            result: .passed
        )

        let argumentsTrue = TestResultsDTO.TestNode(
            children: [repetition3],
            durationInSeconds: nil,
            name: "true",
            nodeIdentifier: nil,
            nodeIdentifierURL: nil,
            nodeType: .arguments,
            result: nil
        )

        let device = TestResultsDTO.TestNode(
            children: [argumentsFalse, argumentsTrue],
            durationInSeconds: nil,
            name: "iPhone 13",
            nodeIdentifier: nil,
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
                        name: "First Run", type: .repetition),
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
                        name: "First Run", type: .repetition),
                ],
            ])
    }
}
