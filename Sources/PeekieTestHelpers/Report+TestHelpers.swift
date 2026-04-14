import Foundation

@testable import PeekieSDK

extension Report {
    public static func testMake(
        modules: Set<Module> = [],
        coverage: Double? = nil
    ) -> Self {
        // Calculate coverage from files if not provided
        let calculatedCoverage: Double?
        if let coverage = coverage {
            calculatedCoverage = coverage
        } else {
            let fileCoverages = modules.flatMap { $0.files }.compactMap { $0.coverage }
            if fileCoverages.count > 0 {
                let totalLines = fileCoverages.reduce(into: 0) { $0 += $1.totalLines }
                let totalCoveredLines = fileCoverages.reduce(into: 0) { $0 += $1.coveredLines }
                if totalLines != 0 {
                    calculatedCoverage = Double(totalCoveredLines) / Double(totalLines)
                } else {
                    calculatedCoverage = 0.0
                }
            } else {
                calculatedCoverage = nil
            }
        }
        return .init(
            modules: modules,
            coverage: calculatedCoverage
        )
    }
}

extension Report.Module {
    public static func testMake(
        name: String = "",
        suites: Set<Suite> = [],
        files: Set<File> = [],
        repeatableTests: Set<Suite.RepeatableTest> = [],
        coverage: Report.Coverage? = nil
    ) -> Self {
        .init(
            name: name, suites: suites, repeatableTests: repeatableTests, files: files,
            coverage: coverage)
    }
}

extension Report.Module.File.Coverage {
    public static func testMake(
        coveredLines: Int = 0,
        totalLines: Int = 0,
        coverage: Double = 0.0
    ) -> Self {
        Self(
            coveredLines: coveredLines,
            totalLines: totalLines,
            coverage: coverage)
    }
}

extension Report.Module.File {
    public static func testMake(
        name: String = "",
        warnings: [Report.Module.File.Issue] = [],
        coverage: Report.Module.File.Coverage? = nil
    ) -> Self {
        .init(name: name, warnings: warnings, coverage: coverage)
    }
}

extension Report.Module.Suite {
    public static func testMake(
        name: String = "",
        nodeIdentifierURL: String = "",
        suites: Set<Report.Module.Suite> = [],
        repeatableTests: Set<RepeatableTest> = []
    ) -> Self {
        .init(
            name: name,
            nodeIdentifierURL: nodeIdentifierURL,
            suites: suites,
            repeatableTests: repeatableTests
        )
    }
}

extension Report.Module.Suite.RepeatableTest {
    public static func testMake(
        name: String = "",
        nodeIdentifier: String = "",
        tests: [Test] = []
    ) -> Self {
        .init(name: name, nodeIdentifier: nodeIdentifier, tests: tests)
    }

    public static func failed(
        named name: String,
        times: Int = 1
    ) -> Self {
        let tests = Array(
            repeating: Report.Module.Suite.RepeatableTest.Test.testMake(
                name: name,
                status: .failure),
            count: times
        )
        return .testMake(name: name, tests: tests)
    }

    public static func succeeded(
        named name: String
    ) -> Self {
        .testMake(name: name, tests: [.testMake(name: name, status: .success)])
    }

    public static func skipped(
        named name: String
    ) -> Self {
        .testMake(name: name, tests: [.testMake(name: name, status: .skipped)])
    }

    public static func expectedFailed(
        named name: String
    ) -> Self {
        .testMake(name: name, tests: [.testMake(name: name, status: .expectedFailure)])
    }

    public static func mixedFailedSucceeded(
        named name: String,
        failedTimes: Int = 1
    ) -> Self {
        let failedTests = Array(
            repeating: Report.Module.Suite.RepeatableTest.Test.testMake(
                name: name, status: .failure),
            count: failedTimes
        )
        return .testMake(name: name, tests: failedTests + [.testMake(name: name, status: .success)])
    }
}

extension Report.Module.Suite.RepeatableTest.Test {
    public static func testMake(
        name: String = "",
        status: Status = .success,
        duration: Measurement<UnitDuration> = .testMake(),
        path: [Report.Module.Suite.RepeatableTest.PathNode] = [],
        failureMessage: String? = nil,
        skipMessage: String? = nil
    ) -> Self {
        .init(
            name: name,
            status: status,
            duration: duration,
            path: path,
            failureMessage: failureMessage,
            skipMessage: skipMessage
        )
    }
}
