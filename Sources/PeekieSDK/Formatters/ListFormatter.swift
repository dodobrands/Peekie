import Foundation
import Logging

// MARK: - ListFormatter

/// Formatter that generates human-readable list output of test results
///
/// This formatter produces plain text output with test statuses represented by emoji icons.
/// Ideal for terminal output and CI/CD logs.
///
/// Example output (`.bySuite`):
/// ```
/// ExamplesTests / (no suite)
/// ✅ rootLevelSuccess()
/// ❌ rootLevelFailure() (Expected 5.0 but got 6.0)
///
/// ExamplesTests / OuterSuite
/// ✅ outerSuccess()
///
/// ExamplesTests / OuterSuite / InnerSuite
/// ✅ innerSuccess()
/// ```
public final class ListFormatter {
    // MARK: Lifecycle

    /// Creates a new list formatter instance
    public init() {}

    // MARK: Public

    /// Controls how tests are grouped in the formatted output.
    public enum Grouping {
        /// Each test is printed on its own line with the full module/suite path
        /// prefix, e.g. `"✅ ExamplesTests / OuterSuite / innerSuccess()"`. Lines
        /// are sorted lexicographically by qualified name. Useful when piping
        /// into `grep` or producing flat reports.
        case fullyQualified

        /// Tests are grouped under section headers of the form
        /// `"<Module> / <Suite-path>"` (or `"<Module> / (no suite)"` for
        /// root-level `@Test`s). This is the closest match to the historical
        /// per-suite layout.
        case bySuite
    }

    /// Formats a given report based on specified criteria.
    ///
    /// This method takes a `Report` instance and formats it according to the provided parameters.
    /// It allows filtering based on the status of tests within the report.
    ///
    /// - Parameters:
    ///   - report: The report model instance to be formatted.
    ///   - include: An array of `Report.Module.Suite.RepeatableTest.Test.Status` values that
    /// specifies which test statuses to include in the formatted report.
    ///   - includeDeviceDetails: If true, device information is included in test names. Defaults to
    /// false.
    ///   - grouping: Layout strategy — `.bySuite` (default, with section headers) or
    /// `.fullyQualified` (one fully qualified line per test).
    ///
    /// - Returns: A formatted string representation of the report based on the specified criteria.
    public func format(
        _ report: Report,
        include: [Report.Module.Suite.RepeatableTest.Test.Status] = Report.Module
            .Suite.RepeatableTest.Test.Status.allCases,
        includeDeviceDetails: Bool = false,
        grouping: Grouping = .fullyQualified
    )
        -> String
    {
        logger.debug(
            "Formatting report",
            metadata: [
                "modulesCount": "\(report.modules.count)",
                "includeStatuses": "\(include.map(\.rawValue).joined(separator: ","))",
                "includeDeviceDetails": "\(includeDeviceDetails)",
                "grouping": "\(grouping)",
            ]
        )

        let sections = collectSections(
            report: report,
            include: include,
            includeDeviceDetails: includeDeviceDetails
        )

        let output: String =
            switch grouping {
            case .bySuite:
                renderBySuite(sections: sections)
            case .fullyQualified:
                renderFullyQualified(sections: sections)
            }

        logger.debug(
            "Formatting completed",
            metadata: [
                "sectionsCount": "\(sections.count)",
            ]
        )

        return output
    }

    // MARK: Private

    /// One emit-ready section: the header path (`"<Module> / <Suite-path>"` or
    /// `"<Module> / (no suite)"`), the qualifying prefix used in `.fullyQualified`
    /// mode (same as header but without the `(no suite)` placeholder), and the
    /// already-merged tests in sorted order.
    private struct Section {
        let header: String
        let qualifiedPrefix: String
        let tests: [Report.Module.Suite.RepeatableTest.Test]
    }

    private let logger = Logger(label: "com.peekie.formatter")

    private func collectSections(
        report: Report,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        includeDeviceDetails: Bool
    )
        -> [Section]
    {
        var sections = [Section]()
        for module in report.modules.sorted(by: { $0.name < $1.name }) {
            // Root-level @Tests first (so the bundle's loose tests stay above the
            // suite hierarchy in the human-readable view).
            let rootTests = mergedTests(
                from: report.rootLevelTests(in: module),
                include: include,
                includeDeviceDetails: includeDeviceDetails
            )
            if rootTests.isEmpty == false {
                sections.append(.init(
                    header: "\(module.name) / (no suite)",
                    qualifiedPrefix: module.name,
                    tests: rootTests
                ))
            }

            let suiteSections = report.suites(in: module)
                .flatMap { collectSuiteSections(
                    suite: $0,
                    moduleName: module.name,
                    include: include,
                    includeDeviceDetails: includeDeviceDetails
                ) }
                .sorted { $0.header < $1.header }
            sections.append(contentsOf: suiteSections)
        }
        return sections
    }

    private func collectSuiteSections(
        suite: Report.Module.Suite,
        moduleName: String,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        includeDeviceDetails: Bool
    )
        -> [Section]
    {
        var sections = [Section]()
        let tests = mergedTests(
            from: suite.repeatableTests,
            include: include,
            includeDeviceDetails: includeDeviceDetails
        )
        if tests.isEmpty == false {
            let prefix = "\(moduleName) / \(suite.fullPath)"
            sections.append(.init(header: prefix, qualifiedPrefix: prefix, tests: tests))
        }
        for nested in suite.nestedSuites {
            sections.append(contentsOf: collectSuiteSections(
                suite: nested,
                moduleName: moduleName,
                include: include,
                includeDeviceDetails: includeDeviceDetails
            ))
        }
        return sections
    }

    private func mergedTests(
        from repeatableTests: Set<Report.Module.Suite.RepeatableTest>,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        includeDeviceDetails: Bool
    )
        -> [Report.Module.Suite.RepeatableTest.Test]
    {
        let filtered = repeatableTests
            .filtered(testResults: include)
            .sorted { $0.name < $1.name }

        var merged = [Report.Module.Suite.RepeatableTest.Test]()
        for repeatable in filtered {
            let tests = repeatable
                .mergedTests(filterDevice: includeDeviceDetails == false)
                .filter { include.contains($0.status) }
            merged.append(contentsOf: tests)
        }
        return merged.sorted { $0.name < $1.name }
    }

    private func renderBySuite(sections: [Section]) -> String {
        sections.map { section in
            let rows = [section.header] + section.tests.map { $0.report() }
            return rows.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    private func renderFullyQualified(sections: [Section]) -> String {
        var lines = [String]()
        for section in sections {
            for test in section.tests {
                let qualifiedName = "\(section.qualifiedPrefix) / \(test.name)"
                lines.append(test.report(name: qualifiedName))
            }
        }
        return lines.sorted().joined(separator: "\n")
    }
}

private extension Report.Module.Suite.RepeatableTest.Test {
    func report(name overrideName: String? = nil) -> String {
        [
            status.icon,
            overrideName ?? name,
            message.map { "(\($0))" },
        ]
        .compactMap(\.self)
        .joined(separator: " ")
    }
}
