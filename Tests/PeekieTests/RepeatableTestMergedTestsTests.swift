import Foundation
import Testing

@testable import PeekieSDK

@Suite
struct RepeatableTestMergedTestsTests {

    @Test
    func mergedTestsFromDeviceAndMultipleRepetitions() throws {
        // Variant 1: Device -> Repetition (First Run, Retry 1, Retry 2)
        // Should merge into one test with status from Device
        let repetition1 = Report.Module.Suite.RepeatableTest.PathNode(
            name: "First Run",
            type: .repetition,
            result: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
        )

        let repetition2 = Report.Module.Suite.RepeatableTest.PathNode(
            name: "Retry 1",
            type: .repetition,
            result: .success,
            duration: Measurement(value: 50, unit: .milliseconds),
        )

        let repetition3 = Report.Module.Suite.RepeatableTest.PathNode(
            name: "Retry 2",
            type: .repetition,
            result: .success,
            duration: Measurement(value: 30, unit: .milliseconds),
        )

        let device = Report.Module.Suite.RepeatableTest.PathNode(
            name: "iPhone 13",
            type: .device,
            result: .success,
            duration: Measurement(value: 200, unit: .milliseconds),
        )

        let test1 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
            path: [device, repetition1]
        )

        let test2 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .success,
            duration: Measurement(value: 50, unit: .milliseconds),
            path: [device, repetition2]
        )

        let test3 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .success,
            duration: Measurement(value: 30, unit: .milliseconds),
            path: [device, repetition3]
        )

        let repeatableTest = Report.Module.Suite.RepeatableTest(
            name: "testExample()",
            nodeIdentifier: "Module/testExample()",
            tests: [test1, test2, test3],
        )

        let merged = repeatableTest.mergedTests(filterDevice: true)

        #expect(
            merged == [
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample()",
                    status: .success,
                    duration: Measurement(value: 180, unit: .milliseconds),  // Sum: 100 + 50 + 30
                    path: [])
            ])
    }

    @Test
    func mergedTestsFromDeviceArgumentsAndRepetitions() throws {
        // Variant 2: Device -> Arguments -> Repetition (First Run, Retry 1)
        // Should merge into one test with status from Arguments
        let repetition1 = Report.Module.Suite.RepeatableTest.PathNode(
            name: "First Run",
            type: .repetition,
            result: .failure,
            duration: Measurement(value: 100, unit: .milliseconds),
            message: "Test failed"
        )

        let repetition2 = Report.Module.Suite.RepeatableTest.PathNode(
            name: "Retry 1",
            type: .repetition,
            result: .failure,
            duration: Measurement(value: 50, unit: .milliseconds),
            message: "Test failed"
        )

        let arguments = Report.Module.Suite.RepeatableTest.PathNode(
            name: "false",
            type: .arguments,
            result: .failure,
            duration: Measurement(value: 200, unit: .milliseconds),
            message: "Argument test failed"
        )

        let device = Report.Module.Suite.RepeatableTest.PathNode(
            name: "iPhone 13",
            type: .device,
            result: nil,
            duration: nil,
        )

        let test1 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .failure,
            duration: Measurement(value: 100, unit: .milliseconds),
            path: [device, arguments, repetition1]
        )

        let test2 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .failure,
            duration: Measurement(value: 50, unit: .milliseconds),
            path: [device, arguments, repetition2]
        )

        let repeatableTest = Report.Module.Suite.RepeatableTest(
            name: "testExample()",
            nodeIdentifier: "Module/testExample()",
            tests: [test1, test2]
        )

        let merged = repeatableTest.mergedTests(filterDevice: true)

        #expect(
            merged == [
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample() [false]",
                    status: .failure,
                    duration: Measurement(value: 150, unit: .milliseconds),  // Sum: 100 + 50
                    path: [
                        Report.Module.Suite.RepeatableTest.PathNode(
                            name: "false", type: .arguments, result: .failure,
                            duration: Measurement(value: 200, unit: .milliseconds),
                            message: "Argument test failed")
                    ])
            ])
    }

    @Test
    func mergedTestsFromDifferentArguments() throws {
        // Variant 3: Device -> Arguments(false) -> Repetition
        //           Device -> Arguments(true) -> Repetition
        // Should remain two tests with statuses from respective Arguments
        let repetition1 = Report.Module.Suite.RepeatableTest.PathNode(
            name: "First Run",
            type: .repetition,
            result: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
        )

        let repetition2 = Report.Module.Suite.RepeatableTest.PathNode(
            name: "First Run",
            type: .repetition,
            result: .success,
            duration: Measurement(value: 80, unit: .milliseconds),
        )

        let argumentsFalse = Report.Module.Suite.RepeatableTest.PathNode(
            name: "false",
            type: .arguments,
            result: .failure,
            duration: Measurement(value: 200, unit: .milliseconds),
            message: "False argument failed"
        )

        let argumentsTrue = Report.Module.Suite.RepeatableTest.PathNode(
            name: "true",
            type: .arguments,
            result: .success,
            duration: Measurement(value: 150, unit: .milliseconds),
        )

        let device = Report.Module.Suite.RepeatableTest.PathNode(
            name: "iPhone 13",
            type: .device,
            result: nil,
            duration: nil,
        )

        let test1 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
            path: [device, argumentsFalse, repetition1]
        )

        let test2 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .success,
            duration: Measurement(value: 80, unit: .milliseconds),
            path: [device, argumentsTrue, repetition2]
        )

        let repeatableTest = Report.Module.Suite.RepeatableTest(
            name: "testExample()",
            nodeIdentifier: "Module/testExample()",
            tests: [test1, test2],
        )

        let merged = repeatableTest.mergedTests(filterDevice: true)

        #expect(
            merged == [
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample() [false]",
                    status: .failure,  // Status from argumentsFalse
                    duration: Measurement(value: 100, unit: .milliseconds),  // Sum: 100
                    // Message from repeatableTest (tests.first?.message)
                    path: [
                        Report.Module.Suite.RepeatableTest.PathNode(
                            name: "false", type: .arguments, result: .failure,
                            duration: Measurement(value: 200, unit: .milliseconds),
                            message: "False argument failed")
                    ]),
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample() [true]",
                    status: .success,  // Status from argumentsTrue
                    duration: Measurement(value: 80, unit: .milliseconds),  // Sum: 80
                    // Message from repeatableTest (tests.first?.message)
                    path: [
                        Report.Module.Suite.RepeatableTest.PathNode(
                            name: "true", type: .arguments, result: .success,
                            duration: Measurement(value: 150, unit: .milliseconds),
                        )
                    ]),
            ])
    }

    @Test
    func mergedTestsFromArgumentsAndRepetitions() throws {
        // Variant 4: Arguments -> Repetition (First Run, Retry 1)
        // Should merge into one test with status from Arguments
        let repetition1 = Report.Module.Suite.RepeatableTest.PathNode(
            name: "First Run",
            type: .repetition,
            result: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
        )

        let repetition2 = Report.Module.Suite.RepeatableTest.PathNode(
            name: "Retry 1",
            type: .repetition,
            result: .success,
            duration: Measurement(value: 50, unit: .milliseconds),
        )

        let arguments = Report.Module.Suite.RepeatableTest.PathNode(
            name: "false",
            type: .arguments,
            result: .success,
            duration: Measurement(value: 200, unit: .milliseconds),
        )

        let test1 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
            path: [arguments, repetition1]
        )

        let test2 = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .success,
            duration: Measurement(value: 50, unit: .milliseconds),
            path: [arguments, repetition2]
        )

        let repeatableTest = Report.Module.Suite.RepeatableTest(
            name: "testExample()",
            nodeIdentifier: "Module/testExample()",
            tests: [test1, test2],
        )

        let merged = repeatableTest.mergedTests(filterDevice: true)

        #expect(
            merged == [
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample() [false]",
                    status: .success,
                    duration: Measurement(value: 150, unit: .milliseconds),  // Sum: 100 + 50
                    path: [
                        Report.Module.Suite.RepeatableTest.PathNode(
                            name: "false", type: .arguments, result: .success,
                            duration: Measurement(value: 200, unit: .milliseconds),
                        )
                    ])
            ])
    }

    @Test
    func mergedTestsWithDifferentRepetitionStatuses() throws {
        // Test that if repetitions have different statuses, result is mixed
        let repetition1 = Report.Module.Suite.RepeatableTest.PathNode(
            name: "First Run",
            type: .repetition,
            result: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
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
            duration: Measurement(value: 200, unit: .milliseconds),
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
            nodeIdentifier: "Module/testExample()",
            tests: [test1, test2],
        )

        let merged = repeatableTest.mergedTests(filterDevice: true)

        #expect(
            merged == [
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample()",
                    status: .mixed,
                    duration: Measurement(value: 150, unit: .milliseconds),  // Sum: 100 + 50
                    path: [])
            ])
    }

    @Test
    func mergedTestsWithoutRepetitions() throws {
        // Tests without repetitions should remain unchanged
        let device = Report.Module.Suite.RepeatableTest.PathNode(
            name: "iPhone 13",
            type: .device,
            result: .success,
            duration: Measurement(value: 200, unit: .milliseconds),
        )

        let arguments = Report.Module.Suite.RepeatableTest.PathNode(
            name: "false",
            type: .arguments,
            result: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
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
            nodeIdentifier: "Module/testExample()",
            tests: [test1, test2],
        )

        let merged = repeatableTest.mergedTests(filterDevice: false)

        #expect(
            merged == [
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample() [iPhone 13]",
                    status: .success,
                    duration: Measurement(value: 200, unit: .milliseconds),  // Sum: 200
                    path: [
                        Report.Module.Suite.RepeatableTest.PathNode(
                            name: "iPhone 13", type: .device, result: .success,
                            duration: Measurement(value: 200, unit: .milliseconds),
                        )
                    ]),
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample() [iPhone 13, false]",
                    status: .success,
                    duration: Measurement(value: 100, unit: .milliseconds),  // Sum: 100
                    path: [
                        Report.Module.Suite.RepeatableTest.PathNode(
                            name: "iPhone 13", type: .device, result: .success,
                            duration: Measurement(value: 200, unit: .milliseconds),
                        ),
                        Report.Module.Suite.RepeatableTest.PathNode(
                            name: "false", type: .arguments, result: .success,
                            duration: Measurement(value: 100, unit: .milliseconds),
                        ),
                    ]),
            ])
    }

    @Test
    func mergedTestsWithSingleRepetition() throws {
        // Single test with repetition should merge (remove repetition)
        let repetition = Report.Module.Suite.RepeatableTest.PathNode(
            name: "First Run",
            type: .repetition,
            result: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
        )

        let device = Report.Module.Suite.RepeatableTest.PathNode(
            name: "iPhone 13",
            type: .device,
            result: .success,
            duration: Measurement(value: 200, unit: .milliseconds),
        )

        let test = Report.Module.Suite.RepeatableTest.Test(
            name: "testExample()",
            status: .success,
            duration: Measurement(value: 100, unit: .milliseconds),
            path: [device, repetition]
        )

        let repeatableTest = Report.Module.Suite.RepeatableTest(
            name: "testExample()",
            nodeIdentifier: "Module/testExample()",
            tests: [test],
        )

        let merged = repeatableTest.mergedTests(filterDevice: true)

        #expect(
            merged == [
                Report.Module.Suite.RepeatableTest.Test(
                    name: "testExample()",
                    status: .success,
                    duration: Measurement(value: 100, unit: .milliseconds),  // Sum: 100
                    path: [])
            ])
    }

    @Test
    func mergedTestsWithEmptyTests() throws {
        // Empty tests should return empty array
        let repeatableTest = Report.Module.Suite.RepeatableTest(
            name: "testExample()",
            nodeIdentifier: "Module/testExample()",
            tests: [],
        )

        let merged = repeatableTest.mergedTests(filterDevice: false)

        #expect(merged.isEmpty)
    }
}
