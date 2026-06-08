import Foundation
import PeekieTestHelpers
import SnapshotTesting
import Testing
@testable import PeekieSDK

struct ListFormatterSnapshotTests {
    let formatter = PeekieSDK.ListFormatter()

    @Test(arguments: Constants.testsReportFileNames)
    func format_allStatuses(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)
        let formatted = formatter.format(report, grouping: .bySuite)

        assertSnapshot(
            of: formatted,
            as: .lines,
            named: "\(snapshotName(from: fileName))_all"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func format_successOnly(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)
        let formatted = formatter.format(
            report,
            include: [.success],
            grouping: .bySuite
        )

        assertSnapshot(
            of: formatted,
            as: .lines,
            named: "\(snapshotName(from: fileName))_success"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func format_failureOnly(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)
        let formatted = formatter.format(
            report,
            include: [.failure],
            grouping: .bySuite
        )

        assertSnapshot(
            of: formatted,
            as: .lines,
            named: "\(snapshotName(from: fileName))_failure"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func format_skippedOnly(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)
        let formatted = formatter.format(
            report,
            include: [.skipped],
            grouping: .bySuite
        )

        assertSnapshot(
            of: formatted,
            as: .lines,
            named: "\(snapshotName(from: fileName))_skipped"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func format_fullyQualified_allStatuses(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)
        let formatted = formatter.format(report, grouping: .fullyQualified)

        assertSnapshot(
            of: formatted,
            as: .lines,
            named: "\(snapshotName(from: fileName))_fq_all"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func format_fullyQualified_failureOnly(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)
        let formatted = formatter.format(
            report,
            include: [.failure],
            grouping: .fullyQualified
        )

        assertSnapshot(
            of: formatted,
            as: .lines,
            named: "\(snapshotName(from: fileName))_fq_failure"
        )
    }
}
