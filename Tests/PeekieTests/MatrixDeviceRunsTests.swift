import Foundation
import Testing
@testable import PeekieSDK

/// A matrix run without retries (one test plan, several destinations) reports each
/// destination as `Test Case -> Device -> Failure Message`, with no Repetition nodes.
struct MatrixDeviceRunsTests {
    // MARK: Internal

    @Test
    func eachDeviceBecomesItsOwnRun() {
        let repeatable = Report.buildRepeatableTest(from: matrixTestCase)

        #expect(repeatable.tests.count == 2)
        #expect(repeatable.tests.map { $0.path.first?.name } == ["iPad mini", "iPhone 15"])
        #expect(repeatable.tests.map(\.failureMessage) == ["Navigation failed", "Audit 0.8 < 0.9"])
    }

    @Test
    func deviceDetailsKeepEveryDeviceMessage() {
        let merged = Report.buildRepeatableTest(from: matrixTestCase)
            .mergedTests(filterDevice: false)

        #expect(merged.map(\.name) == [
            "test_favorites() [iPad mini]",
            "test_favorites() [iPhone 15]",
        ])
        #expect(merged.map(\.message) == ["Navigation failed", "Audit 0.8 < 0.9"])
    }

    @Test
    func withoutDeviceDetailsDevicesCollapseToOneTest() {
        let merged = Report.buildRepeatableTest(from: matrixTestCase)
            .mergedTests(filterDevice: true)

        #expect(merged.map(\.name) == ["test_favorites()"])
        #expect(merged.map(\.status) == [.failure])
        #expect(merged.map(\.message) == ["Navigation failed"])
    }

    // MARK: Private

    private var matrixTestCase: TestResultsDTO.TestNode {
        makeNode(
            name: "test_favorites()",
            nodeType: .testCase,
            result: .failed,
            children: [
                makeDevice("iPad mini", message: "File.swift:10: failed - Navigation failed"),
                makeDevice("iPhone 15", message: "File.swift:20: failed - Audit 0.8 < 0.9"),
            ]
        )
    }

    private func makeDevice(_ name: String, message: String) -> TestResultsDTO.TestNode {
        makeNode(
            name: name,
            nodeType: .device,
            result: .failed,
            children: [makeNode(name: message, nodeType: .failureMessage)]
        )
    }

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
