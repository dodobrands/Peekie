import Foundation
import PeekieTestHelpers
import SnapshotTesting
import Testing
@testable import PeekieSDK

struct JSONFormatterSnapshotTests {
    // MARK: Internal

    struct LoadedReport {
        let report: Report
        let outputDir: URL
        let cleanup: () -> Void
    }

    let formatter = PeekieSDK.JSONFormatter()

    @Test(arguments: Constants.testsReportFileNames)
    func jsonFormat_allStatuses(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)
        let formatted = try formatter.format(report, grouping: .bySuite)

        assertSnapshot(
            of: formatted,
            as: .lines,
            named: "\(snapshotName(from: fileName))_json_all"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func jsonFormat_failureOnly(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)
        let formatted = try formatter.format(
            report,
            grouping: .bySuite,
            include: [.failure]
        )

        assertSnapshot(
            of: formatted,
            as: .lines,
            named: "\(snapshotName(from: fileName))_json_failure"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func jsonFormat_fullyQualified_allStatuses(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)
        let formatted = try formatter.format(report, grouping: .fullyQualified)

        assertSnapshot(
            of: formatted,
            as: .lines,
            named: "\(snapshotName(from: fileName))_json_fq_all"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func jsonFormat_fullyQualified_failureOnly(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)
        let formatted = try formatter.format(
            report,
            grouping: .fullyQualified,
            include: [.failure]
        )

        assertSnapshot(
            of: formatted,
            as: .lines,
            named: "\(snapshotName(from: fileName))_json_fq_failure"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func jsonFormat_withAttachments_allStatuses(_ fileName: String) async throws {
        let loaded = try await loadReportWithAttachments(fileName: fileName)
        defer { loaded.cleanup() }

        let formatted = try formatter.format(loaded.report, grouping: .bySuite)

        assertSnapshot(
            of: normalize(formatted, outputDir: loaded.outputDir),
            as: .lines,
            named: "\(snapshotName(from: fileName))_json_attachments_all"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func jsonFormat_withAttachments_failureOnly(_ fileName: String) async throws {
        let loaded = try await loadReportWithAttachments(fileName: fileName)
        defer { loaded.cleanup() }

        let formatted = try formatter.format(
            loaded.report,
            grouping: .bySuite,
            include: [.failure]
        )

        assertSnapshot(
            of: normalize(formatted, outputDir: loaded.outputDir),
            as: .lines,
            named: "\(snapshotName(from: fileName))_json_attachments_failure"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func jsonFormat_fullyQualified_withAttachments_allStatuses(_ fileName: String) async throws {
        let loaded = try await loadReportWithAttachments(fileName: fileName)
        defer { loaded.cleanup() }

        let formatted = try formatter.format(loaded.report, grouping: .fullyQualified)

        assertSnapshot(
            of: normalize(formatted, outputDir: loaded.outputDir),
            as: .lines,
            named: "\(snapshotName(from: fileName))_json_fq_attachments_all"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func jsonFormat_fullyQualified_withAttachments_failureOnly(_ fileName: String) async throws {
        let loaded = try await loadReportWithAttachments(fileName: fileName)
        defer { loaded.cleanup() }

        let formatted = try formatter.format(
            loaded.report,
            grouping: .fullyQualified,
            include: [.failure]
        )

        assertSnapshot(
            of: normalize(formatted, outputDir: loaded.outputDir),
            as: .lines,
            named: "\(snapshotName(from: fileName))_json_fq_attachments_failure"
        )
    }

    // MARK: Private

    private func loadReportWithAttachments(
        fileName: String
    ) async throws
        -> LoadedReport
    {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        let outputDir = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let report = try await Report(
            xcresultPath: reportPath,
            attachments: .extractTo(outputDir)
        )

        return LoadedReport(report: report, outputDir: outputDir) {
            try? FileManager.default.removeItem(at: reportPath)
            try? FileManager.default.removeItem(at: outputDir)
        }
    }

    private func normalize(_ output: String, outputDir: URL) -> String {
        let raw = outputDir.path
        let jsonEscaped = raw.replacing("/", with: "\\/")
        return output
            .replacing(jsonEscaped, with: "<ATTACHMENTS_DIR>")
            .replacing(raw, with: "<ATTACHMENTS_DIR>")
    }
}
