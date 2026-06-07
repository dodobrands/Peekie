import Foundation
import PeekieTestHelpers
import SnapshotTesting
import Testing
@testable import PeekieSDK

struct SonarFormatterSnapshotTests {
    // MARK: Internal

    let formatter = SonarFormatter()

    @Test(arguments: Constants.testsReportFileNames)
    func sonarFormat_allStatuses(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)

        // Create temporary test directory with mock test files.
        // Include `fileName` in the path so parallel parameterized cases don't share
        // (and thus race-delete) the same directory.
        let testsPath = try createTestDirectory(
            for: report,
            slug: "\(#function)-\(snapshotName(from: fileName))"
        )
        defer {
            try? FileManager.default.removeItem(at: testsPath)
        }

        let formatted = try formatter.format(report: report, testsPath: testsPath)

        // Normalize paths in snapshot to avoid CI/local differences
        let normalized = normalizePaths(in: formatted)

        assertSnapshot(
            of: normalized,
            as: .lines,
            named: "\(snapshotName(from: fileName))_sonar"
        )
    }

    // MARK: Private

    // MARK: - Helpers

    private func createTestDirectory(for report: Report, slug: String) throws -> URL {
        // Use slug (function + fixture) in temporary directory for stable snapshot paths per test
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("PeekieSonarTests-\(slug)")

        // Remove existing directory if present to ensure clean state
        if FileManager.default.fileExists(atPath: testDir.path) {
            try? FileManager.default.removeItem(at: testDir)
        }
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        // Generate mock Swift test files based on test suite names from the report
        // Only include files that have tests (skip coverage-only files)
        let testSuites = Set(
            report.modules.flatMap {
                $0.suites.filter { $0.repeatableTests.isEmpty == false }.map(\.name)
            }
        )

        for testSuiteName in testSuites {
            // Create a simple Swift file with the test suite class/struct
            // Check if name already has .swift extension
            let fileName =
                testSuiteName.hasSuffix(".swift") ? testSuiteName : "\(testSuiteName).swift"
            let filePath = testDir.appendingPathComponent(fileName)

            // Remove .swift extension for struct name
            let structName =
                testSuiteName.hasSuffix(".swift")
                    ? String(testSuiteName.dropLast(6))
                    : testSuiteName

            // Generate minimal Swift test file content
            let fileContent = """
            import Foundation
            import Testing

            @Suite
            struct \(structName) {
                // Mock test suite for snapshot testing
            }
            """

            try fileContent.write(to: filePath, atomically: true, encoding: .utf8)
        }

        // Return standardized URL to avoid /private/var vs /var issues
        return URL(fileURLWithPath: testDir.path).standardized
    }

    private func normalizePaths(in xml: String) -> String {
        // Find the marker "PeekieSonarTests-" in paths and replace everything before it with
        // {TEMP_DIR}/
        let marker = "PeekieSonarTests-"

        // Use regex to match path="...PeekieSonarTests-..." and replace everything before marker
        // with {TEMP_DIR}/
        // Pattern matches: path="(anything)PeekieSonarTests-(rest of path)"
        let pattern =
            #"path="[^"]*"# + NSRegularExpression.escapedPattern(for: marker) + #"([^"]*)""#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return xml
        }

        let range = NSRange(xml.startIndex..., in: xml)
        return regex.stringByReplacingMatches(
            in: xml,
            options: [],
            range: range,
            withTemplate: #"path="{TEMP_DIR}/$1""#
        )
    }
}
