// swiftlint:disable:next blanket_disable_command
// swiftlint:disable missing_docs
import Foundation
@testable import PeekieSDK

public extension Report {
    static func testMake(
        files: [File] = [],
        modules: [Module] = [],
        coverage: Double? = nil
    )
        -> Self
    {
        // Calculate coverage from files if not provided
        let calculatedCoverage: Double?
        if let coverage {
            calculatedCoverage = coverage
        } else {
            let fileCoverages = files.compactMap(\.coverage)
            if fileCoverages.isEmpty == false {
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
            files: files,
            modules: modules,
            coverage: calculatedCoverage
        )
    }
}

public extension Report.Module {
    static func testMake(
        name: String = "",
        files: [Report.File] = [],
        coverage: Report.Coverage? = nil,
        suites: [Suite] = []
    )
        -> Self
    {
        .init(name: name, files: files, coverage: coverage, suites: suites)
    }
}

public extension Report.File.Coverage {
    static func testMake(
        coveredLines: Int = 0,
        totalLines: Int = 0,
        coverage: Double = 0.0
    )
        -> Self
    {
        Self(
            coveredLines: coveredLines,
            totalLines: totalLines,
            coverage: coverage
        )
    }
}

public extension Report.File {
    static func testMake(
        name: String = "",
        path: String? = nil,
        module: String? = nil,
        coverage: Report.File.Coverage? = nil,
        warnings: [Report.File.Issue] = [],
        errors: [Report.File.Issue] = []
    )
        -> Self
    {
        .init(
            name: name,
            path: path,
            module: module,
            coverage: coverage,
            warnings: warnings,
            errors: errors
        )
    }
}

public extension Report.Module.Suite {
    static func testMake(
        name: String = "",
        nodeIdentifierURL: String = "",
        repeatableTests: Set<RepeatableTest> = []
    )
        -> Self
    {
        .init(
            name: name,
            nodeIdentifierURL: nodeIdentifierURL,
            repeatableTests: repeatableTests
        )
    }
}

public extension Report.Module.Suite.RepeatableTest {
    static func testMake(
        name: String = "",
        tests: [Test] = []
    )
        -> Self
    {
        .init(name: name, tests: tests)
    }

    static func failed(
        named name: String,
        times: Int = 1
    )
        -> Self
    {
        let tests = Array(
            repeating: Self.Test.testMake(
                name: name,
                status: .failure
            ),
            count: times
        )
        return .testMake(name: name, tests: tests)
    }

    static func succeeded(
        named name: String
    )
        -> Self
    {
        .testMake(name: name, tests: [.testMake(name: name, status: .success)])
    }

    static func skipped(
        named name: String
    )
        -> Self
    {
        .testMake(name: name, tests: [.testMake(name: name, status: .skipped)])
    }

    static func expectedFailed(
        named name: String
    )
        -> Self
    {
        .testMake(name: name, tests: [.testMake(name: name, status: .expectedFailure)])
    }

    static func mixedFailedSucceeded(
        named name: String,
        failedTimes: Int = 1
    )
        -> Self
    {
        let failedTests = Array(
            repeating: Self.Test.testMake(
                name: name, status: .failure
            ),
            count: failedTimes
        )
        return .testMake(name: name, tests: failedTests + [.testMake(name: name, status: .success)])
    }
}

public extension Report.Module.Suite.RepeatableTest.Test {
    static func testMake(
        name: String = "",
        status: Status = .success,
        duration: Measurement<UnitDuration> = .testMake(),
        path: [Report.Module.Suite.RepeatableTest.PathNode] = [],
        failureMessage: String? = nil,
        skipMessage: String? = nil
    )
        -> Self
    {
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
