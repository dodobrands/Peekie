import Foundation
import Testing
@testable import PeekieSDK

struct RepeatableTestMergedTestsExtraTests {
    @Test
    func mergedTestsWithDifferentRepetitionStatuses() {
        // Test that if repetitions have different statuses, result is mixed
        let repetition1 = Report.Module.Suite.RepeatableTest.PathNode(
            name: "First Run",
            type: .repetition,
            result: .success,
            duration: Measurement(value: 100, unit: .milliseconds)
        )

        let repetition2 = Report.Module.Suite.RepeatableTest.PathNode(
            name: "Retry 1",
            type: .repetition,
            result: .failure,
            duration: Measurement(value: 50, unit: .milliseconds),
            message: "Failed on retry"
        )

        let device = Report.Module.Suite.RepeatableTest.PathNode(
            name: "iPhone 13",
            type: .device,
            result: .success,
            duration: Measurement(value: 200, unit: .milliseconds)
        )

        let test1 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
            path: [device, repetition1]
        )

        let test2 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .failure,
            duration: Measurement(value: 50, unit: .milliseconds),
            path: [device, repetition2]
        )

        let repeatableTest = Report.Module.Suite.RepeatableTest(
            name: "testExample()",
            tests: [test1, test2]
        )

        let merged = repeatableTest.mergedTests(filterDevice: true)

        #expect(
            merged == [
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample()",
                    status: .mixed,
                    duration: Measurement(value: 150, unit: .milliseconds), // Sum: 100 + 50
                    path: []
                ),
            ]
        )
    }

    @Test
    func mergedTestsWithoutRepetitions() {
        // Tests without repetitions should remain unchanged
        let device = Report.Module.Suite.RepeatableTest.PathNode(
            name: "iPhone 13",
            type: .device,
            result: .success,
            duration: Measurement(value: 200, unit: .milliseconds)
        )

        let arguments = Report.Module.Suite.RepeatableTest.PathNode(
            name: "false",
            type: .arguments,
            result: .success,
            duration: Measurement(value: 100, unit: .milliseconds)
        )

        let test1 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .success,
            duration: Measurement(value: 200, unit: .milliseconds),
            path: [device]
        )

        let test2 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
            path: [device, arguments]
        )

        let repeatableTest = Report.Module.Suite.RepeatableTest(
            name: "testExample()",
            tests: [test1, test2]
        )

        let merged = repeatableTest.mergedTests(filterDevice: false)

        #expect(
            merged == [
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample() [iPhone 13]",
                    status: .success,
                    duration: Measurement(value: 200, unit: .milliseconds), // Sum: 200
                    path: [
                        Report.Module.Suite.RepeatableTest.PathNode(
                            name: "iPhone 13", type: .device, result: .success,
                            duration: Measurement(value: 200, unit: .milliseconds)
                        ),
                    ]
                ),
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample() [iPhone 13, false]",
                    status: .success,
                    duration: Measurement(value: 100, unit: .milliseconds), // Sum: 100
                    path: [
                        Report.Module.Suite.RepeatableTest.PathNode(
                            name: "iPhone 13", type: .device, result: .success,
                            duration: Measurement(value: 200, unit: .milliseconds)
                        ),
                        Report.Module.Suite.RepeatableTest.PathNode(
                            name: "false", type: .arguments, result: .success,
                            duration: Measurement(value: 100, unit: .milliseconds)
                        ),
                    ]
                ),
            ]
        )
    }

    @Test
    func mergedTestsWithSingleRepetition() {
        // Single test with repetition should merge (remove repetition)
        let repetition = Report.Module.Suite.RepeatableTest.PathNode(
            name: "First Run",
            type: .repetition,
            result: .success,
            duration: Measurement(value: 100, unit: .milliseconds)
        )

        let device = Report.Module.Suite.RepeatableTest.PathNode(
            name: "iPhone 13",
            type: .device,
            result: .success,
            duration: Measurement(value: 200, unit: .milliseconds)
        )

        let test = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
            path: [device, repetition]
        )

        let repeatableTest = Report.Module.Suite.RepeatableTest(
            name: "testExample()",
            tests: [test]
        )

        let merged = repeatableTest.mergedTests(filterDevice: true)

        #expect(
            merged == [
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample()",
                    status: .success,
                    duration: Measurement(value: 100, unit: .milliseconds), // Sum: 100
                    path: []
                ),
            ]
        )
    }

    @Test
    func mergedTestsWithEmptyTests() {
        // Empty tests should return empty array
        let repeatableTest = Report.Module.Suite.RepeatableTest(
            name: "testExample()",
            tests: []
        )

        let merged = repeatableTest.mergedTests(filterDevice: false)

        #expect(merged.isEmpty)
    }
}
