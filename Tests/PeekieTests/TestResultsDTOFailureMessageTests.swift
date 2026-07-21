import Foundation
import Testing
@testable import PeekieSDK

/// `xcresulttool merge` inserts structural wrapper nodes (Device/Arguments)
/// between a test case and its Failure Message, so message extraction must
/// descend through them: an unmerged bundle has `Test Case → Failure Message`,
/// a merged one `Test Case → Device → Failure Message`.
struct TestResultsDTOFailureMessageTests {
    // MARK: Internal

    @Test
    func failureMessageFromDirectChild() {
        let testCase = makeNode(
            name: "test_example()",
            nodeType: .testCase,
            result: .failed,
            children: [
                makeNode(
                    name: "File.swift:51: failed - Направление не выбрано",
                    nodeType: .failureMessage
                ),
            ]
        )

        #expect(testCase.failureMessage == "Направление не выбрано")
    }

    @Test
    func failureMessageThroughDeviceWrapper() {
        // Merged bundle: Test Case -> Device -> Failure Message
        let testCase = makeNode(
            name: "test_example()",
            nodeType: .testCase,
            result: .failed,
            children: [
                makeNode(
                    name: "iPhone 13",
                    nodeType: .device,
                    result: .failed,
                    children: [
                        makeNode(
                            name: "File.swift:84: failed - Не удалось выбрать тип заказа",
                            nodeType: .failureMessage
                        ),
                    ]
                ),
            ]
        )

        #expect(testCase.failureMessage == "Не удалось выбрать тип заказа")
    }

    @Test
    func failureMessageThroughDeviceAndArguments() {
        // Merged parameterized test: Test Case -> Device -> Arguments -> Failure Message
        let testCase = makeNode(
            name: "test_example(value:)",
            nodeType: .testCase,
            result: .failed,
            children: [
                makeNode(
                    name: "iPhone 13",
                    nodeType: .device,
                    result: .failed,
                    children: [
                        makeNode(
                            name: "value: 42",
                            nodeType: .arguments,
                            result: .failed,
                            children: [
                                makeNode(
                                    name: "File.swift:12: Issue recorded: Wrong answer",
                                    nodeType: .failureMessage
                                ),
                            ]
                        ),
                    ]
                ),
            ]
        )

        #expect(testCase.failureMessage == "Wrong answer")
    }

    @Test
    func failureMessageDoesNotEnterRepetitions() {
        // Each repetition owns its message: the test case level must not leak it
        let testCase = makeNode(
            name: "test_example()",
            nodeType: .testCase,
            result: .failed,
            children: [
                makeNode(
                    name: "iPhone 13",
                    nodeType: .device,
                    result: .failed,
                    children: [
                        makeNode(
                            name: "Repetition 1 of 3",
                            nodeType: .repetition,
                            result: .failed,
                            children: [
                                makeNode(
                                    name: "File.swift:1: failed - Only mine",
                                    nodeType: .failureMessage
                                ),
                            ]
                        ),
                    ]
                ),
            ]
        )

        #expect(testCase.failureMessage == nil)
    }

    @Test
    func dimensionNodesStayScopedToDirectChildren() {
        // A device node must not surface a message owned by an arguments node
        // beneath it — only test cases search through wrappers
        let device = makeNode(
            name: "iPhone 13",
            nodeType: .device,
            result: .failed,
            children: [
                makeNode(
                    name: "value: 42",
                    nodeType: .arguments,
                    result: .failed,
                    children: [
                        makeNode(
                            name: "File.swift:12: failed - Argument message",
                            nodeType: .failureMessage
                        ),
                    ]
                ),
            ]
        )

        #expect(device.failureMessage == nil)
    }

    @Test
    func skipMessageThroughDeviceWrapper() {
        let testCase = makeNode(
            name: "test_example()",
            nodeType: .testCase,
            result: .skipped,
            children: [
                makeNode(
                    name: "iPhone 13",
                    nodeType: .device,
                    result: .skipped,
                    children: [
                        makeNode(
                            name: "Test skipped - Not supported on CI",
                            nodeType: .failureMessage
                        ),
                    ]
                ),
            ]
        )

        #expect(testCase.skipMessage == "Not supported on CI")
    }

    @Test
    func argumentsInitPrefersOwnMessageOverTestCase() {
        let failedArguments = makeNode(
            name: "value: 42",
            nodeType: .arguments,
            result: .failed,
            children: [
                makeNode(
                    name: "File.swift:12: failed - Argument-specific message",
                    nodeType: .failureMessage
                ),
            ]
        )

        let testCase = makeNode(
            name: "test_example(value:)",
            nodeType: .testCase,
            result: .failed,
            children: [
                makeNode(
                    name: "File.swift:12: failed - Case-level message",
                    nodeType: .failureMessage
                ),
                failedArguments,
            ]
        )

        let test = Report.Module.Suite.RepeatableTest.Test(
            from: failedArguments,
            path: [],
            testCase: testCase
        )

        #expect(test.failureMessage == "Argument-specific message")
    }

    // MARK: Private

    private func makeNode(
        name: String,
        nodeType: TestResultsDTO.TestNode.NodeType,
        result: TestResultsDTO.TestNode.Result? = nil,
        children: [TestResultsDTO.TestNode]? = nil
    )
        -> TestResultsDTO.TestNode
    {
        TestResultsDTO.TestNode(
            children: children,
            durationInSeconds: nil,
            name: name,
            nodeIdentifierURL: nil,
            nodeType: nodeType,
            result: result
        )
    }
}
