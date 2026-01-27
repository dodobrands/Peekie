import Foundation
import PeekieTestHelpers
import SnapshotTesting
import Testing

@testable import PeekieSDK

@Suite
struct JsonFormatterSnapshotTests {
    let formatter = PeekieSDK.JsonFormatter()

    @Test(arguments: Constants.testsReportFileNames)
    func jsonFormat_allStatuses(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)
        let formatted = try formatter.format(report)

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
            include: [.failure]
        )

        assertSnapshot(
            of: formatted,
            as: .lines,
            named: "\(snapshotName(from: fileName))_json_failure"
        )
    }
}
