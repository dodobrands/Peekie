import Foundation

// MARK: - Report.Module.Suite.RepeatableTest

public extension Report.Module.Suite {
    /// A test that can be run multiple times (e.g., with retries, different devices, or
    /// parameterized inputs)
    struct RepeatableTest: Hashable {
        // MARK: Lifecycle

        init(name: String, tests: [Test], nodeIdentifier: String? = nil) {
            self.name = name
            self.tests = tests
            self.nodeIdentifier = nodeIdentifier
        }

        // MARK: Public

        /// Name of the test (e.g., "test_example()")
        public let name: String

        /// Array of test executions (multiple entries if test was retried or run with different
        /// parameters)
        public internal(set) var tests: [Test]

        /// Canonical test identifier from the test-case node in xcresult JSON, e.g.
        /// `"SuiteTests/test_example()"` or ``"SuiteTests/`display name`()"``.
        /// Unlike `name` (a display name for Swift Testing tests), the identifier is
        /// stable — for parameterized tests it is the function signature
        /// (`getValue(input:expected:)`), which no display-name heuristic can
        /// reconstruct. Exporters that need stable test identity (e.g.
        /// ``AllureFormatter``) rely on it.
        public let nodeIdentifier: String?

        public static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.name == rhs.name
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
    }
}

// MARK: - Report.Module.Suite.RepeatableTest + CustomReflectable

extension Report.Module.Suite.RepeatableTest: CustomReflectable {
    /// Omits `nodeIdentifier` from `Mirror`-based dumps (e.g. `swift-snapshot-testing`'s
    /// `.dump` strategy). The identifier is exporter plumbing that duplicates `name`
    /// for most tests; hiding it keeps snapshots recorded before the field existed
    /// byte-for-byte stable, so adding it is non-breaking for downstream consumers
    /// that snapshot `Report`.
    public var customMirror: Mirror {
        let children: [Mirror.Child] = [
            ("name", name),
            ("tests", tests),
        ]
        return Mirror(self, children: children, displayStyle: .struct)
    }
}

public extension Report.Module.Suite.RepeatableTest {
    /// A node in the test execution path representing device, arguments, or repetition
    struct PathNode: Equatable, Hashable {
        // MARK: Lifecycle

        init(
            name: String,
            type: NodeType,
            result: Test.Status? = nil,
            duration: Measurement<UnitDuration>? = nil,
            message: String? = nil
        ) {
            self.name = name
            self.type = type
            self.result = result
            self.duration = duration
            self.message = message
        }

        // MARK: Public

        /// Types of path nodes in test execution hierarchy
        public enum NodeType: Equatable, Hashable {
            /// Device on which test was executed (e.g., "iPhone 15 Pro")
            case device

            /// Test arguments for parameterized tests
            case arguments

            /// Test repetition/retry
            case repetition

            // MARK: Lifecycle

            init(from dtoNodeType: TestResultsDTO.TestNode.NodeType) {
                switch dtoNodeType {
                case .device:
                    self = .device
                case .arguments:
                    self = .arguments
                case .repetition:
                    self = .repetition
                default:
                    // This should not happen in normal flow, but handle gracefully
                    fatalError("Cannot convert \(dtoNodeType) to PathNode.NodeType")
                }
            }
        }

        /// Name of the path node (e.g., device name, argument value, or repetition number)
        public let name: String

        /// Type of this path node
        public let type: NodeType

        /// Test result at this path node level (if available)
        public let result: Test.Status?

        /// Duration of execution at this path node level (if available)
        public let duration: Measurement<UnitDuration>?

        /// Message associated with this path node (e.g., failure or skip reason)
        public let message: String?
    }

    /// A single test execution with its result, duration, and execution path
    struct Test: Equatable {
        // MARK: Lifecycle

        public init(
            name: String,
            status: Status,
            duration: Measurement<UnitDuration>,
            path: [PathNode],
            failureMessage: String? = nil,
            skipMessage: String? = nil,
            attachments: [Attachment] = []
        ) {
            self.name = name
            self.status = status
            self.duration = duration
            self.path = path
            self.failureMessage = failureMessage
            self.skipMessage = skipMessage
            self.attachments = attachments
        }

        // MARK: Public

        /// Name of the test
        public let name: String

        /// Execution status of the test
        public let status: Status

        /// Duration of the test execution
        public let duration: Measurement<UnitDuration>

        /// Execution path showing device, arguments, and repetitions
        public let path: [PathNode]

        /// Failure message if test failed
        public let failureMessage: String?

        /// Skip message if test was skipped
        public let skipMessage: String?

        /// Attachments captured during this test execution. Empty unless the
        /// `Report` was built with `attachments: .extractTo(_)`.
        public internal(set) var attachments: [Attachment]

        /// Returns the appropriate message based on test status
        /// - For failures: returns failureMessage
        /// - For expected failures: returns failureMessage or "Failure is expected"
        /// - For skipped: returns skipMessage
        /// - For mixed: returns failureMessage
        /// - For other statuses: returns nil
        public var message: String? {
            switch status {
            case .failure:
                failureMessage
            case .expectedFailure:
                failureMessage ?? "Failure is expected"
            case .skipped:
                skipMessage
            case .mixed:
                failureMessage
            default:
                nil
            }
        }
    }

    /// Combined status of all test executions (mixed if statuses differ)
    var combinedStatus: Test.Status {
        let statuses = tests.map(\.status)
        if statuses.elementsAreEqual {
            return statuses.first ?? .success
        }
        return .mixed
    }

    /// Average duration across all test executions
    var averageDuration: Measurement<UnitDuration> {
        assert(tests.map(\.duration.unit).elementsAreEqual)

        let unit = tests.first?.duration.unit ?? Test.defaultDurationUnit

        return .init(
            value: tests.map(\.duration.value).average(),
            unit: unit
        )
    }

    /// Total duration of all test executions combined
    var totalDuration: Measurement<UnitDuration> {
        assert(tests.map(\.duration.unit).elementsAreEqual)
        let value = tests.map(\.duration.value).sum()
        let unit = tests.first?.duration.unit ?? Test.defaultDurationUnit
        return .init(value: value, unit: unit)
    }

    /// Returns merged tests by merging repetitions (removing repetition nodes from paths)
    /// Status is mixed if repetitions had different statuses, otherwise uses parent node status
    /// - Parameter filterDevice: If true, device nodes are filtered from the path. Defaults to
    /// false.
    /// - Returns: Array of merged tests
    func mergedTests(filterDevice: Bool = false) -> [Test] {
        guard tests.isEmpty == false else {
            return []
        }

        let pathToTests = groupTests(filterDevice: filterDevice)
        let merged = pathToTests.keys.sorted().compactMap { key -> Test? in
            guard let group = pathToTests[key] else {
                return nil
            }

            return mergeGroup(group, filterDevice: filterDevice)
        }

        return merged.sorted { pathKey(from: $0.path) < pathKey(from: $1.path) }
    }

    private func groupTests(filterDevice: Bool) -> [String: [Test]] {
        var pathToTests = [String: [Test]]()
        for test in tests {
            let key = pathKey(from: filter(test.path, filterDevice: filterDevice))
            pathToTests[key, default: []].append(test)
        }
        return pathToTests
    }

    private func mergeGroup(_ group: [Test], filterDevice: Bool) -> Test {
        let pathForResult = filter(group[0].path, filterDevice: filterDevice)
        let status = mergedStatus(group: group, pathForResult: pathForResult)
        return Test(
            name: mergedName(path: pathForResult),
            status: status,
            duration: Measurement(
                value: group.map(\.duration.value).sum(),
                unit: Test.defaultDurationUnit
            ),
            path: pathForResult,
            failureMessage: failureMessage(group: group, status: status),
            skipMessage: skipMessage(group: group, status: status),
            attachments: mergedAttachments(group: group)
        )
    }

    private func mergedAttachments(group: [Test]) -> [Test.Attachment] {
        var seen = Set<String>()
        var result = [Test.Attachment]()
        for test in group {
            for attachment in test.attachments
                where seen.insert(attachment.exportedFileName).inserted
            {
                result.append(attachment)
            }
        }
        return result
    }

    private func filter(_ path: [PathNode], filterDevice: Bool) -> [PathNode] {
        path.filter { node in
            if node.type == .repetition {
                return false
            }
            if filterDevice, node.type == .device {
                return false
            }
            return true
        }
    }

    private func mergedName(path: [PathNode]) -> String {
        let elements = path.map(\.name)
        return elements.isEmpty ? name : "\(name) [\(elements.joined(separator: ", "))]"
    }

    private func mergedStatus(group: [Test], pathForResult: [PathNode]) -> Test.Status {
        let statuses = group.map(\.status)
        if statuses.elementsAreEqual == false {
            return .mixed
        }
        return pathForResult.last?.result ?? statuses.first ?? .unknown
    }

    private func failureMessage(group: [Test], status: Test.Status) -> String? {
        guard status == .failure || status == .mixed else {
            return nil
        }

        return group.first { $0.status == .failure }?.failureMessage ?? group.first?.failureMessage
    }

    private func skipMessage(group: [Test], status: Test.Status) -> String? {
        guard status == .skipped else {
            return nil
        }

        return group.first { $0.status == .skipped }?.skipMessage ?? group.first?.skipMessage
    }

    private func pathKey(from path: [PathNode]) -> String {
        path.map { "\($0.name):\($0.type)" }.joined(separator: "|")
    }

    /// Checks if this test is considered slow based on a threshold duration
    /// - Parameter duration: The threshold duration to compare against
    /// - Returns: True if average duration meets or exceeds the threshold
    func isSlow(_ duration: Measurement<UnitDuration>) -> Bool {
        let averageDuration = averageDuration
        let duration = duration.converted(to: averageDuration.unit)
        return averageDuration >= duration
    }
}
