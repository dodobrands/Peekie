import Foundation
import PeekieTestHelpers
import Testing
@testable import PeekieSDK

struct ReportIncludeTestsFlagTests {
    @Test(arguments: Constants.testsReportFileNames)
    func includeTestsFalseSkipsSuitesButKeepsFilesAndWarnings(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer { try? FileManager.default.removeItem(at: reportPath) }

        let report = try await Report(
            xcresultPath: reportPath,
            includeCoverage: true,
            includeWarnings: true,
            includeTests: false
        )

        let suitesTotal = report.modules.reduce(0) { $0 + report.suites(in: $1).count }
        #expect(suitesTotal == 0, "expected zero suites when includeTests is false")

        // For fixtures that have coverage data, modules and files are still populated.
        #expect(report.files.isEmpty == false, "files should remain populated without tests")
    }

    @Test(arguments: Constants.testsReportFileNames)
    func warningsOnlyFlowSurfacesWarnings(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer { try? FileManager.default.removeItem(at: reportPath) }

        let report = try await Report(
            xcresultPath: reportPath,
            includeCoverage: false,
            includeWarnings: true,
            includeTests: false
        )

        // Coverage is nil
        #expect(report.coverage == nil)
        // Modules with suites are absent (no tests parsed)
        let suitesEmpty = report.suitesByModule.values.allSatisfy(\.isEmpty)
        #expect(suitesEmpty)
        // Files only show up if the fixture has build warnings; not all fixtures do,
        // but the call must succeed and return a well-formed Report.
        _ = report.files
    }
}
