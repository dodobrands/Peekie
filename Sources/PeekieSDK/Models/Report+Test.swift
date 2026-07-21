import Foundation

// MARK: - Report.Module.Suite.RepeatableTest.Test.Status

public extension Report.Module.Suite.RepeatableTest.Test {
    /// Test execution status
    enum Status: String, Equatable, CaseIterable {
        /// Test passed successfully
        case success

        /// Test failed
        case failure

        /// Test failed as expected (marked with XCTExpectFailure)
        case expectedFailure

        /// Test was skipped
        case skipped

        /// Test had multiple retries with different results (flaky test)
        case mixed

        /// Test status is unknown or could not be determined
        case unknown
    }
}

extension Set<Report.Module.Suite.RepeatableTest> {
    /// Filters tests based on statis
    /// - Parameter testResults: statuses to leave in result
    /// - Returns: set of elements matching any of the specified statuses
    public func filtered(testResults: [Report.Module.Suite.RepeatableTest.Test.Status])
        -> Set<Element>
    {
        guard testResults.isEmpty == false else {
            return self
        }

        let results =
            testResults
                .flatMap { testResult -> Set<Element> in
                    switch testResult {
                    case .success:
                        return self.succeeded
                    case .failure:
                        return self.failed
                    case .mixed:
                        return self.mixed
                    case .skipped:
                        return self.skipped
                    case .expectedFailure:
                        return self.expectedFailed
                    case .unknown:
                        return self.unknown
                    }
                }

        return Set(results)
    }

    /// Property that filters the collection to include only elements whose status is `.success`.
    var succeeded: Self {
        filter { $0.combinedStatus == .success }
    }

    /// Property that filters the collection to include only elements whose status is `.failure`.
    var failed: Self {
        filter { $0.combinedStatus == .failure }
    }

    /// Property that filters the collection to include only elements whose status is
    /// `.expectedFailure`.
    var expectedFailed: Self {
        filter { $0.combinedStatus == .expectedFailure }
    }

    /// Property that filters the collection to include only elements whose status is `.skipped`.
    var skipped: Self {
        filter { $0.combinedStatus == .skipped }
    }

    /// Property that filters the collection to include only elements whose status is `.mixed`.
    /// This might indicate a combination of success and failure statuses or an intermediate state.
    var mixed: Self {
        filter { $0.combinedStatus == .mixed }
    }

    /// Property that filters the collection to include only elements whose status is `.unknown`.
    /// This status might be used when the status of an element has not been determined or is not
    /// applicable.
    var unknown: Self {
        filter { $0.combinedStatus == .unknown }
    }
}

extension Report.Module.Suite.RepeatableTest.Test {
    /// Initializes from TestResultsDTO.TestNode (Repetition node) with path
    init(
        from node: TestResultsDTO.TestNode,
        path: [Report.Module.Suite.RepeatableTest.PathNode],
        testCaseName: String,
        testCase: TestResultsDTO.TestNode? = nil
    ) throws {
        guard node.nodeType == .repetition else {
            throw Error.invalidNodeType
        }
        guard let result = node.result else {
            throw Error.missingResult
        }

        name = testCaseName

        switch result {
        case .passed:
            status = .success
        case .failed:
            status = .failure
        case .skipped:
            status = .skipped
        case .expectedFailure:
            status = .expectedFailure
        }

        let durationSeconds = node.durationInSeconds ?? 0.0
        duration = .init(value: durationSeconds * 1000, unit: Self.defaultDurationUnit)

        self.path = path

        // Extract messages from repetition node itself (failure messages are in repetition
        // children)
        // Fallback to testCase if repetition doesn't have messages (e.g., for expected failures)
        failureMessage = node.failureMessage ?? testCase?.failureMessage
        skipMessage = node.skipMessage ?? testCase?.skipMessage
        attachments = []
    }

    /// Initializes from TestResultsDTO.TestNode (Arguments node) with path
    init(
        from node: TestResultsDTO.TestNode,
        path: [Report.Module.Suite.RepeatableTest.PathNode],
        testCase: TestResultsDTO.TestNode
    ) {
        name = testCase.name

        let status: Status
        if let result = node.result {
            switch result {
            case .passed:
                status = .success
            case .failed:
                status = .failure
            case .skipped:
                status = .skipped
            case .expectedFailure:
                status = .expectedFailure
            }
        } else {
            // Fallback to test case result
            guard let testCaseResult = testCase.result else {
                status = .unknown
                self.status = status
                duration = .init(value: 0, unit: Self.defaultDurationUnit)
                self.path = path
                failureMessage = nil
                skipMessage = nil
                attachments = []
                return
            }

            switch testCaseResult {
            case .passed:
                status = .success
            case .failed:
                status = .failure
            case .skipped:
                status = .skipped
            case .expectedFailure:
                status = .expectedFailure
            }
        }

        self.status = status

        let durationSeconds = node.durationInSeconds ?? testCase.durationInSeconds ?? 0.0
        duration = .init(value: durationSeconds * 1000, unit: Self.defaultDurationUnit)

        self.path = path

        // Prefer the arguments node's own messages so each argument set keeps its
        // message; fall back to testCase metadata
        failureMessage = node.failureMessage ?? testCase.failureMessage
        skipMessage = node.skipMessage ?? testCase.skipMessage
        attachments = []
    }

    /// Initializes from TestResultsDTO.TestNode (Test Case node) with empty path
    init(from testCase: TestResultsDTO.TestNode) {
        name = testCase.name

        guard let result = testCase.result else {
            status = .unknown
            duration = .init(value: 0, unit: Self.defaultDurationUnit)
            path = []
            failureMessage = nil
            skipMessage = nil
            attachments = []
            return
        }

        switch result {
        case .passed:
            status = .success
        case .failed:
            status = .failure
        case .skipped:
            status = .skipped
        case .expectedFailure:
            status = .expectedFailure
        }

        let durationSeconds = testCase.durationInSeconds ?? 0.0
        duration = .init(value: durationSeconds * 1000, unit: Self.defaultDurationUnit)

        path = []

        // Extract messages from testCase metadata
        failureMessage = testCase.failureMessage
        skipMessage = testCase.skipMessage
        attachments = []
    }

    enum Error: Swift.Error {
        case invalidNodeType
        case missingResult
    }

    static let defaultDurationUnit = UnitDuration.milliseconds
}
