import Foundation

// MARK: - Report

/// Parsed report from an `.xcresult` file.
///
/// `files` is the primary index — every file we have any signal about (coverage,
/// warnings, errors) lives here exactly once, regardless of which target it
/// belongs to. `modules` is a projection over `files` for the subset where a
/// target name is known. Build issues with no module signal (`xcresulttool`
/// doesn't currently surface `producingTarget` for them) still surface — they
/// appear in `files` with `File.module == nil` and are reachable via
/// `Report.warnings` / `Report.errors`.
public struct Report {
    // MARK: Lifecycle

    public init(
        files: [File],
        modules: [Module],
        coverage: Double?
    ) {
        self.files = files
        self.modules = modules
        self.coverage = coverage
    }

    // MARK: Public

    /// Every file the bundle has any signal about (coverage, warnings, errors).
    public let files: [File]

    /// Module projection — one entry per target name we could identify
    /// (from coverage or from tests). Files whose target is unknown are
    /// **not** represented here; reach them via `files`.
    public let modules: [Module]

    /// Total code coverage percentage (0.0 to 1.0).
    /// - Note: Read directly from xcresult coverage data (not calculated from files).
    public let coverage: Double?

    /// All warnings from all files in this report.
    public var warnings: [File.Issue] {
        files.flatMap(\.warnings)
    }

    /// All errors from all files in this report.
    public var errors: [File.Issue] {
        files.flatMap(\.errors)
    }
}

public extension Report {
    /// A source file with coverage, warnings, and errors information.
    ///
    /// `File` is the primary entity in the model — every data source xcresult
    /// emits identifies files by `sourceURL` or coverage path. `module` is the
    /// only optional identity field: build-issue records don't carry target
    /// ownership, so a file known only from `warnings[]` / `errors[]` has
    /// `module == nil`. Identity (hash, equality) is `path ?? name`: two files
    /// with the same basename but different paths are distinct.
    struct File: Hashable {
        // MARK: Lifecycle

        public init(
            name: String,
            path: String? = nil,
            module: String? = nil,
            coverage: Coverage? = nil,
            warnings: [Issue] = [],
            errors: [Issue] = []
        ) {
            self.name = name
            self.path = path
            self.module = module
            self.coverage = coverage
            self.warnings = warnings
            self.errors = errors
        }

        // MARK: Public

        /// Basename of the file (e.g., "Report.swift").
        public let name: String

        /// Absolute path when xcresult provided one (coverage and warnings/errors do).
        public let path: String?

        /// Owning target name when known. `nil` for files known only from
        /// build issues (xcresult doesn't emit `producingTarget` for those).
        public let module: String?

        /// Code coverage for this file when present.
        public let coverage: Coverage?

        /// Build warnings on this file.
        public let warnings: [Issue]

        /// Build errors on this file.
        public let errors: [Issue]

        public static func ==(lhs: Self, rhs: Self) -> Bool {
            (lhs.path ?? lhs.name) == (rhs.path ?? rhs.name)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(path ?? name)
        }
    }

    /// Projection over `Report.files` grouped by target name.
    ///
    /// `Module` is built from coverage targets and test bundles — the two data
    /// sources xcresult emits that name a target. A module's `files` slice is
    /// every `Report.files` entry whose `File.module` matches; `suites` is the
    /// tests xcresult reported for that target.
    struct Module: Hashable {
        // MARK: Lifecycle

        public init(
            name: String,
            files: [File] = [],
            coverage: Coverage? = nil,
            suites: [Suite] = []
        ) {
            self.name = name
            self.files = files
            self.coverage = coverage
            self.suites = suites
        }

        // MARK: Public

        /// Target name (e.g., "Bonuses", "PeekieTests").
        public let name: String

        /// Files in this report whose `File.module == self.name`.
        public let files: [File]

        /// Target-level coverage when xcresult reported one.
        public let coverage: Coverage?

        /// Test suites this target ran.
        public let suites: [Suite]

        /// All warnings from all files in this module.
        public var warnings: [File.Issue] {
            files.flatMap(\.warnings)
        }

        /// All errors from all files in this module.
        public var errors: [File.Issue] {
            files.flatMap(\.errors)
        }

        public static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.name == rhs.name
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
    }

    /// Aggregate code coverage at the module or report scope.
    struct Coverage: Equatable {
        // MARK: Lifecycle

        public init(coveredLines: Int, totalLines: Int, coverage: Double) {
            self.coveredLines = coveredLines
            self.totalLines = totalLines
            self.coverage = coverage
        }

        // MARK: Public

        public let coveredLines: Int
        public let totalLines: Int
        public let coverage: Double
    }
}

public extension Report.File {
    /// Code coverage information for a specific file.
    struct Coverage: Equatable {
        // MARK: Lifecycle

        public init(coveredLines: Int, totalLines: Int, coverage: Double) {
            self.coveredLines = coveredLines
            self.totalLines = totalLines
            self.coverage = coverage
        }

        init(from dto: FileCoverageDTO) {
            coveredLines = dto.coveredLines
            totalLines = dto.executableLines
            coverage = dto.lineCoverage
        }

        // MARK: Public

        public let coveredLines: Int
        public let totalLines: Int
        public let coverage: Double
    }

    /// A build issue (warning or error) associated with a file.
    struct Issue: Equatable, Sendable {
        // MARK: Lifecycle

        public init(type: IssueType, message: String, location: Location? = nil) {
            self.type = type
            self.message = message
            self.location = location
        }

        // MARK: Public

        /// Source range inside a file. `startLine` is the minimum guarantee;
        /// other three fields are independently optional because `xcresulttool`
        /// is not contractually obligated to emit all of them.
        public struct Location: Equatable, Sendable, Codable {
            // MARK: Lifecycle

            public init(
                startLine: Int,
                startColumn: Int? = nil,
                endLine: Int? = nil,
                endColumn: Int? = nil
            ) {
                self.startLine = startLine
                self.startColumn = startColumn
                self.endLine = endLine
                self.endColumn = endColumn
            }

            // MARK: Public

            public let startLine: Int
            public let startColumn: Int?
            public let endLine: Int?
            public let endColumn: Int?
        }

        /// Types of build issues that can be reported.
        ///
        /// The set of `issueType` values emitted by `xcresulttool` is open —
        /// Apple adds new typed diagnostics in newer Xcode releases. Use
        /// `.unknown(_)` for forward compatibility; the raw string is preserved
        /// verbatim.
        public enum IssueType: Equatable, Sendable {
            case swiftCompilerWarning
            case swiftCompilerError
            case deprecatedDeclaration
            case noUsage
            case unknown(String)
        }

        public let type: IssueType
        public let message: String

        /// Source location in the file when xcresult provided one.
        /// `nil` for project-level issues or when the `sourceURL` fragment has
        /// no `StartingLineNumber`.
        public let location: Location?
    }
}

public extension Report.File.Issue.IssueType {
    init(rawValue: String) {
        switch rawValue {
        case "Swift Compiler Warning":
            self = .swiftCompilerWarning
        case "Swift Compiler Error":
            self = .swiftCompilerError
        case "DeprecatedDeclaration":
            self = .deprecatedDeclaration
        case "No-usage":
            self = .noUsage
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .swiftCompilerWarning:
            "Swift Compiler Warning"
        case .swiftCompilerError:
            "Swift Compiler Error"
        case .deprecatedDeclaration:
            "DeprecatedDeclaration"
        case .noUsage:
            "No-usage"
        case .unknown(let raw):
            raw
        }
    }
}

// MARK: - Report.File.Issue.IssueType + Codable

extension Report.File.Issue.IssueType: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(rawValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Report.Module.Suite

public extension Report.Module {
    /// A test suite containing a group of related tests
    struct Suite: Hashable {
        // MARK: Lifecycle

        public init(
            name: String,
            nodeIdentifierURL: String,
            repeatableTests: Set<RepeatableTest> = []
        ) {
            self.name = name
            self.nodeIdentifierURL = nodeIdentifierURL
            self.repeatableTests = repeatableTests
        }

        // MARK: Public

        /// Name of the test suite (e.g., "ReportTests")
        public let name: String

        /// URL identifier from the test node in xcresult JSON.
        /// Examples:
        /// - Test Suite: `"test://com.apple.xcode/Module/ModuleTests/SuiteTests"`
        /// - Test Case: `"test://com.apple.xcode/Module/ModuleTests/SuiteTests/test_example"`
        /// - Unit test bundle: `"test://com.apple.xcode/Module/ModuleTests"`
        /// Format: `test://com.apple.xcode/<Module>/<Bundle>/<Suite>/<TestCase>`
        public let nodeIdentifierURL: String

        /// Set of repeatable tests in this suite
        public internal(set) var repeatableTests: Set<RepeatableTest>

        public static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.name == rhs.name
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
    }
}

// MARK: - Report.Module.Suite.RepeatableTest

public extension Report.Module.Suite {
    /// A test that can be run multiple times (e.g., with retries, different devices, or
    /// parameterized inputs)
    struct RepeatableTest: Hashable {
        /// Name of the test (e.g., "test_example()")
        public let name: String

        /// Array of test executions (multiple entries if test was retried or run with different
        /// parameters)
        public internal(set) var tests: [Test]

        public static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.name == rhs.name
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
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
            skipMessage: String? = nil
        ) {
            self.name = name
            self.status = status
            self.duration = duration
            self.path = path
            self.failureMessage = failureMessage
            self.skipMessage = skipMessage
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
        } else {
            return .mixed
        }
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

        // Group tests by path without repetition (and optionally device) elements
        var pathToTests = [String: [Test]]()

        for test in tests {
            // Remove repetition nodes (always) and device nodes (if filterDevice is true) for
            // grouping
            let pathForGrouping = test.path.filter {
                if $0.type == .repetition {
                    return false
                }
                if filterDevice, $0.type == .device {
                    return false
                }
                return true
            }
            let pathKey = pathKey(from: pathForGrouping)

            if pathToTests[pathKey] == nil {
                pathToTests[pathKey] = []
            }
            pathToTests[pathKey]?.append(test)
        }

        var mergedResults = [Test]()

        // Sort by path key to ensure consistent order
        let sortedKeys = pathToTests.keys.sorted()
        for key in sortedKeys {
            guard let groupTests = pathToTests[key] else {
                continue
            }

            // Remove repetition nodes (always) and device nodes (if filterDevice is true) from path
            let firstTest = groupTests[0]
            let pathForResult = firstTest.path.filter {
                if $0.type == .repetition {
                    return false
                }
                if filterDevice, $0.type == .device {
                    return false
                }
                return true
            }

            // Build name: RepeatableTest name + names of all path elements in brackets
            let pathElementNames = pathForResult.map(\.name)
            let mergedName: String =
                if pathElementNames.isEmpty {
                    name
                } else {
                    "\(name) [\(pathElementNames.joined(separator: ", "))]"
                }

            // Check if statuses differ
            let statuses = groupTests.map(\.status)
            let statusesDiffer = statuses.elementsAreEqual == false

            let parentNode = pathForResult.last
            let status: Test.Status =
                if statusesDiffer {
                    .mixed
                } else {
                    parentNode?.result ?? statuses.first ?? .unknown
                }

            // Sum durations of all tests in the group (all attempts)
            let totalDuration = groupTests.map(\.duration.value).sum()
            let duration = Measurement(value: totalDuration, unit: Test.defaultDurationUnit)

            // Extract messages from merged tests
            // For failures, prefer message from failed test, otherwise use first available
            let failureMessage: String? = {
                if status == .failure || status == .mixed {
                    return groupTests.first(where: { $0.status == .failure })?.failureMessage
                        ?? groupTests.first?.failureMessage
                }
                return nil
            }()

            // For skipped, prefer message from skipped test
            let skipMessage: String? = {
                if status == .skipped {
                    return groupTests.first(where: { $0.status == .skipped })?.skipMessage
                        ?? groupTests.first?.skipMessage
                }
                return nil
            }()

            mergedResults.append(
                Test(
                    name: mergedName,
                    status: status,
                    duration: duration,
                    path: pathForResult,
                    failureMessage: failureMessage,
                    skipMessage: skipMessage
                )
            )
        }

        // Sort results by path for consistent ordering
        return mergedResults.sorted { test1, test2 in
            let key1 = pathKey(from: test1.path)
            let key2 = pathKey(from: test2.path)
            return key1 < key2
        }
    }

    /// Creates a key from path for grouping
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

    /// Property that filters the collection to include only elements whose status is `.expectedFailure`.
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
    /// This status might be used when the status of an element has not been determined or is not applicable.
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

        // Extract messages from testCase metadata
        failureMessage = testCase.failureMessage
        skipMessage = testCase.skipMessage
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
    }

    enum Error: Swift.Error {
        case invalidNodeType
        case missingResult
    }

    static let defaultDurationUnit: UnitDuration = .milliseconds
}

extension Array where Element: Equatable {
    var elementsAreEqual: Bool {
        dropFirst().allSatisfy { $0 == first }
    }
}

public extension [Report.Module.Suite] {
    subscript(_ name: String) -> Element? {
        first { $0.name == name }
    }
}

public extension [Report.File] {
    subscript(_ name: String) -> Element? {
        first { $0.name == name }
    }
}

public extension [Report.Module] {
    subscript(_ name: String) -> Element? {
        first { $0.name == name }
    }
}

public extension [Report.Module.Suite.RepeatableTest] {
    var totalDuration: Measurement<UnitDuration> {
        assert(map(\.totalDuration.unit).elementsAreEqual)
        let value = map(\.totalDuration.value).sum()
        let unit =
            first?.totalDuration.unit
                ?? Report.Module.Suite.RepeatableTest.Test.defaultDurationUnit
        return .init(value: value, unit: unit)
    }
}

public extension Report.Module.Suite.RepeatableTest.Test.Status {
    /// Emoji icon representing the test status
    var icon: String {
        switch self {
        case .success:
            "✅"
        case .failure:
            "❌"
        case .skipped:
            "⏭️"
        case .mixed:
            "⚠️"
        case .expectedFailure:
            "🤡"
        case .unknown:
            "🤷"
        }
    }
}
