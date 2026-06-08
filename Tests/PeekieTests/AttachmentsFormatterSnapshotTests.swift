import Foundation
import PeekieTestHelpers
import SnapshotTesting
import Testing
@testable import PeekieSDK

struct AttachmentsFormatterSnapshotTests {
    // MARK: Internal

    struct LoadedReport {
        let report: Report
        let outputDir: URL
        let cleanup: () -> Void
    }

    let formatter = AttachmentsFormatter()

    @Test(arguments: Constants.testsReportFileNames)
    func attachmentsFormat_json_allStatuses(_ fileName: String) async throws {
        let loaded = try await loadReportWithAttachments(fileName: fileName)
        defer { loaded.cleanup() }

        let formatted = try formatter.json(loaded.report)

        assertSnapshot(
            of: normalize(formatted, outputDir: loaded.outputDir),
            as: .lines,
            named: "\(snapshotName(from: fileName))_attachments_json_all"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func attachmentsFormat_json_failureOnly(_ fileName: String) async throws {
        let loaded = try await loadReportWithAttachments(fileName: fileName)
        defer { loaded.cleanup() }

        let formatted = try formatter.json(loaded.report, include: [.failure])

        assertSnapshot(
            of: normalize(formatted, outputDir: loaded.outputDir),
            as: .lines,
            named: "\(snapshotName(from: fileName))_attachments_json_failure"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func attachmentsFormat_list_allStatuses(_ fileName: String) async throws {
        let loaded = try await loadReportWithAttachments(fileName: fileName)
        defer { loaded.cleanup() }

        let formatted = formatter.list(loaded.report)

        assertSnapshot(
            of: formatted,
            as: .lines,
            named: "\(snapshotName(from: fileName))_attachments_list_all"
        )
    }

    // MARK: Private

    /// Loads a report with attachments extracted to a fresh tmp directory.
    /// The returned `LoadedReport` owns cleanup; tests must `defer { $0.cleanup() }`.
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
            includeCoverage: false,
            includeWarnings: false,
            includeTests: true,
            attachments: .extractTo(outputDir)
        )

        return LoadedReport(report: report, outputDir: outputDir) {
            try? FileManager.default.removeItem(at: reportPath)
            try? FileManager.default.removeItem(at: outputDir)
        }
    }

    /// Replaces the volatile tmp output-dir prefix with a stable placeholder so
    /// snapshots don't churn between runs. Handles both the raw `/`-delimited
    /// form (list output) and the JSON-escaped `\/` form (json output).
    private func normalize(_ output: String, outputDir: URL) -> String {
        let raw = outputDir.path
        let jsonEscaped = raw.replacing("/", with: "\\/")
        return output
            .replacing(jsonEscaped, with: "<ATTACHMENTS_DIR>")
            .replacing(raw, with: "<ATTACHMENTS_DIR>")
    }
}
