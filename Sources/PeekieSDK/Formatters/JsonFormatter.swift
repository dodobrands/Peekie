import Foundation
import Logging

// MARK: - JSONFormatter

/// Formats a `Report` as a pretty-printed JSON tree of modules / suites / tests.
/// Used by `peekie tests --format json`.
public final class JSONFormatter {
    // MARK: Lifecycle

    /// Creates a new formatter.
    public init() {}

    // MARK: Public

    /// Controls how tests are grouped in the JSON output.
    public enum Grouping {
        /// Default nested shape: tests are split between `rootLevelTests` and
        /// `suites[].nestedSuites[].repeatableTests[]`.
        case bySuite

        /// Flat shape: tests collapse into a single `tests` array per module,
        /// with `qualifiedName` strings combining module, suite path, and test name.
        case fullyQualified
    }

    /// Encodes `report` to JSON.
    /// - Parameters:
    ///   - report: The parsed report.
    ///   - grouping: How tests are grouped per module. Defaults to
    ///     `.fullyQualified` (flat per-module `tests` array). Pass
    ///     `.bySuite` for the nested tree shape.
    ///   - include: Test statuses to surface (defaults to all).
    ///   - includeDeviceDetails: When `true`, device names appear in test names
    ///     (`[iPhone 15 Pro]`). Useful for matrix runs.
    public func format(
        _ report: Report,
        grouping: Grouping = .fullyQualified,
        include: [Report.Module.Suite.RepeatableTest.Test.Status] = Report.Module
            .Suite.RepeatableTest.Test.Status.allCases,
        includeDeviceDetails: Bool = false
    ) throws
        -> String
    {
        logger.debug(
            "Formatting report as JSON",
            metadata: [
                "modulesCount": "\(report.modules.count)",
                "grouping": "\(grouping)",
                "includeStatuses": "\(include.map(\.rawValue).joined(separator: ","))",
                "includeDeviceDetails": "\(includeDeviceDetails)",
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        switch grouping {
        case .bySuite:
            let jsonReport = JSONReport(
                from: report,
                include: include,
                includeDeviceDetails: includeDeviceDetails
            )
            data = try encoder.encode(jsonReport)

        case .fullyQualified:
            let jsonReport = JSONReportFlat(
                from: report,
                include: include,
                includeDeviceDetails: includeDeviceDetails
            )
            data = try encoder.encode(jsonReport)
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Private

    private let logger = Logger(label: "com.peekie.formatter.json")
}

// MARK: - JSONReport

private struct JSONReport: Encodable {
    // MARK: Lifecycle

    init(
        from report: Report,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        includeDeviceDetails: Bool
    ) {
        coverage = report.coverage
        modules = report.modules
            .sorted { $0.name < $1.name }
            .map {
                JSONModule(
                    from: $0,
                    include: include,
                    includeDeviceDetails: includeDeviceDetails
                )
            }
    }

    // MARK: Internal

    let coverage: Double?
    let modules: [JSONModule]
}

// MARK: - JSONModule

private struct JSONModule: Encodable {
    // MARK: Lifecycle

    init(
        from module: Report.Module,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        includeDeviceDetails: Bool
    ) {
        name = module.name
        coverage = module.coverage.map { JSONCoverage(from: $0) }
        files = module.files
            .sorted { $0.name < $1.name }
            .map { JSONFile(from: $0) }
        rootLevelTests = module.rootLevelTests
            .filtered(testResults: include)
            .sorted { $0.name < $1.name }
            .flatMap { repeatableTest in
                repeatableTest.mergedTests(filterDevice: includeDeviceDetails == false)
                    .filter { include.contains($0.status) }
                    .map { JSONTest(from: $0) }
            }
        suites = module.suites
            .sorted { $0.fullPath < $1.fullPath }
            .map {
                JSONSuite(
                    from: $0,
                    include: include,
                    includeDeviceDetails: includeDeviceDetails
                )
            }
    }

    // MARK: Internal

    let coverage: JSONCoverage?
    let files: [JSONFile]
    let name: String
    let rootLevelTests: [JSONTest]
    let suites: [JSONSuite]
}

// MARK: - JSONReportFlat

private struct JSONReportFlat: Encodable {
    // MARK: Lifecycle

    init(
        from report: Report,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        includeDeviceDetails: Bool
    ) {
        coverage = report.coverage
        modules = report.modules
            .sorted { $0.name < $1.name }
            .map {
                JSONModuleFlat(
                    from: $0,
                    include: include,
                    includeDeviceDetails: includeDeviceDetails
                )
            }
    }

    // MARK: Internal

    let coverage: Double?
    let modules: [JSONModuleFlat]
}

// MARK: - JSONModuleFlat

private struct JSONModuleFlat: Encodable {
    // MARK: Lifecycle

    init(
        from module: Report.Module,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        includeDeviceDetails: Bool
    ) {
        name = module.name
        coverage = module.coverage.map { JSONCoverage(from: $0) }
        files = module.files
            .sorted { $0.name < $1.name }
            .map { JSONFile(from: $0) }

        var collected = [JSONQualifiedTest]()

        let rootLevelTests = module.rootLevelTests
            .filtered(testResults: include)
            .flatMap { repeatableTest in
                repeatableTest.mergedTests(filterDevice: includeDeviceDetails == false)
                    .filter { include.contains($0.status) }
            }
        for test in rootLevelTests {
            collected.append(
                JSONQualifiedTest(
                    qualifiedName: "\(module.name) / \(test.name)",
                    test: test
                )
            )
        }

        for suite in module.suites {
            Self.collectTests(
                from: suite,
                modulePrefix: module.name,
                include: include,
                includeDeviceDetails: includeDeviceDetails,
                into: &collected
            )
        }

        tests = collected.sorted { $0.qualifiedName < $1.qualifiedName }
    }

    // MARK: Internal

    let coverage: JSONCoverage?
    let files: [JSONFile]
    let name: String
    let tests: [JSONQualifiedTest]

    // MARK: Private

    private static func collectTests(
        from suite: Report.Module.Suite,
        modulePrefix: String,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        includeDeviceDetails: Bool,
        into collected: inout [JSONQualifiedTest]
    ) {
        let suitePrefix = "\(modulePrefix) / \(suite.fullPath)"

        let tests = suite.repeatableTests
            .filtered(testResults: include)
            .flatMap { repeatableTest in
                repeatableTest.mergedTests(filterDevice: includeDeviceDetails == false)
                    .filter { include.contains($0.status) }
            }
        for test in tests {
            collected.append(
                JSONQualifiedTest(
                    qualifiedName: "\(suitePrefix) / \(test.name)",
                    test: test
                )
            )
        }

        for nested in suite.nestedSuites {
            collectTests(
                from: nested,
                modulePrefix: modulePrefix,
                include: include,
                includeDeviceDetails: includeDeviceDetails,
                into: &collected
            )
        }
    }
}

// MARK: - JSONQualifiedTest

private struct JSONQualifiedTest: Encodable {
    // MARK: Lifecycle

    init(qualifiedName: String, test: Report.Module.Suite.RepeatableTest.Test) {
        self.qualifiedName = qualifiedName
        status = test.status.rawValue
        durationMs = test.duration.converted(to: .milliseconds).value
        message = test.message
    }

    // MARK: Internal

    let durationMs: Double
    let message: String?
    let qualifiedName: String
    let status: String
}

// MARK: - JSONCoverage

private struct JSONCoverage: Encodable {
    // MARK: Lifecycle

    init(from coverage: Report.Coverage) {
        coveredLines = coverage.coveredLines
        totalLines = coverage.totalLines
        percentage = coverage.coverage
    }

    init(from coverage: Report.File.Coverage) {
        coveredLines = coverage.coveredLines
        totalLines = coverage.totalLines
        percentage = coverage.coverage
    }

    // MARK: Internal

    let coveredLines: Int
    let percentage: Double
    let totalLines: Int
}

// MARK: - JSONFile

private struct JSONFile: Encodable {
    // MARK: Lifecycle

    init(from file: Report.File) {
        name = file.name
        coverage = file.coverage.map { JSONCoverage(from: $0) }
        warnings = file.warnings.map { JSONIssue(from: $0) }
        errors = file.errors.map { JSONIssue(from: $0) }
    }

    // MARK: Internal

    let coverage: JSONCoverage?
    let name: String
    let warnings: [JSONIssue]
    let errors: [JSONIssue]
}

// MARK: - JSONIssue

private struct JSONIssue: Encodable {
    // MARK: Lifecycle

    init(from issue: Report.File.Issue) {
        type = issue.type.rawValue
        message = issue.message
        location = issue.location
    }

    // MARK: Internal

    let message: String
    let type: String
    let location: Report.File.Issue.Location?
}

// MARK: - JSONSuite

private struct JSONSuite: Encodable {
    // MARK: Lifecycle

    init(
        from suite: Report.Module.Suite,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        includeDeviceDetails: Bool
    ) {
        name = suite.name
        fullPath = suite.fullPath
        tests = suite.repeatableTests
            .filtered(testResults: include)
            .sorted { $0.name < $1.name }
            .flatMap { repeatableTest in
                repeatableTest.mergedTests(filterDevice: includeDeviceDetails == false)
                    .filter { include.contains($0.status) }
                    .map { JSONTest(from: $0) }
            }
        nestedSuites = suite.nestedSuites
            .map {
                Self(
                    from: $0,
                    include: include,
                    includeDeviceDetails: includeDeviceDetails
                )
            }
    }

    // MARK: Internal

    let fullPath: String
    let name: String
    let nestedSuites: [Self]
    let tests: [JSONTest]
}

// MARK: - JSONTest

private struct JSONTest: Encodable {
    // MARK: Lifecycle

    init(from test: Report.Module.Suite.RepeatableTest.Test) {
        name = test.name
        status = test.status.rawValue
        durationMs = test.duration.converted(to: .milliseconds).value
        message = test.message
    }

    // MARK: Internal

    let durationMs: Double
    let message: String?
    let name: String
    let status: String
}
