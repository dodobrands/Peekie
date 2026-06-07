import Foundation
import PeekieTestHelpers
import SnapshotTesting
import Testing
@testable import PeekieSDK

struct ReportSnapshotTests {
    @Test(arguments: Constants.testsReportFileNames)
    func reportSnapshots(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)

        assertSnapshot(
            of: report,
            as: .dump,
            named: snapshotName(from: fileName)
        )
    }
}
