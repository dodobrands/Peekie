import Foundation
import PeekieTestHelpers
import SnapshotTesting
import Testing
@testable import PeekieSDK

// MARK: - AllureFormatterSnapshotTests

struct AllureFormatterSnapshotTests {
    // MARK: Internal

    let formatter = AllureFormatter()

    @Test(arguments: Constants.testsReportFileNames)
    func results_allBundles(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer {
            try? FileManager.default.removeItem(at: reportPath)
        }
        let report = try await Report(xcresultPath: reportPath)

        let results = formatter.results(
            report: report,
            startedAt: Date(timeIntervalSince1970: 0),
            makeUUID: Self.makeSequentialUUID()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = try String(decoding: encoder.encode(results), as: UTF8.self)

        assertSnapshot(
            of: json,
            as: .lines,
            named: "\(snapshotName(from: fileName))_allure"
        )
    }

    @Test(arguments: Constants.testsReportFileNames)
    func write_producesResultFilesAndAttachments(_ fileName: String) async throws {
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        let attachmentsDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("PeekieAllureAttachments-\(UUID().uuidString)")
        let outputDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("PeekieAllureResults-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: reportPath)
            try? FileManager.default.removeItem(at: attachmentsDir)
            try? FileManager.default.removeItem(at: outputDir)
        }

        let report = try await Report(
            xcresultPath: reportPath,
            includeCoverage: false,
            includeWarnings: false,
            attachments: .extractTo(attachmentsDir)
        )

        let summary = try formatter.write(report: report, to: outputDir)

        let files = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
        let resultFiles = files.filter { $0.hasSuffix("-result.json") }
        let attachmentFiles = files.filter { $0.contains("-attachment") }

        #expect(summary.resultsTotal > 0)
        #expect(resultFiles.count == summary.resultsTotal)
        #expect(attachmentFiles.count == summary.attachmentsTotal)
        #expect(summary.resultCountsByStatus.values.reduce(0, +) == summary.resultsTotal)
    }

    // MARK: Private

    /// Deterministic UUID source for stable snapshots: 00000000-0000-0000-0000-000000000001, …
    private static func makeSequentialUUID() -> () -> UUID {
        var counter = 0
        return {
            counter += 1
            let suffix = String(format: "%012d", counter)
            guard let uuid = UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") else {
                fatalError("Invalid sequential UUID for counter \(counter)")
            }

            return uuid
        }
    }
}

// MARK: - AllureFormatterIdentifierTests

struct AllureFormatterIdentifierTests {
    @Test
    func nameFromPlainIdentifier() {
        #expect(
            AllureFormatter.testName(fromIdentifier: "SuiteTests/test_example()")
                == "test_example()"
        )
    }

    @Test
    func nameFromParameterizedIdentifier() {
        #expect(
            AllureFormatter.testName(
                fromIdentifier: "ParserTests/getOpenedTo(schedule:date:expected:)"
            ) == "getOpenedTo(schedule:date:expected:)"
        )
    }

    @Test
    func nameFromNestedSuiteIdentifier() {
        #expect(
            AllureFormatter.testName(fromIdentifier: "Outer/Inner/`display name`()")
                == "`display name`()"
        )
    }

    @Test
    func nameKeepsSlashInsideBackticks() {
        #expect(
            AllureFormatter.testName(
                fromIdentifier: "CartTests/`When A/B enabled, should show icon`()"
            ) == "`When A/B enabled, should show icon`()"
        )
    }

    @Test
    func plainFunctionNameStaysAsIs() {
        #expect(AllureFormatter.legacyTestName("test_example()") == "test_example()")
        #expect(AllureFormatter.legacyTestName("someTest123()") == "someTest123()")
    }

    @Test
    func displayNameIsBacktickWrapped() {
        #expect(
            AllureFormatter.legacyTestName("Given empty cart, then no removals")
                == "`Given empty cart, then no removals`()"
        )
    }

    @Test
    func displayNameWithSlashIsBacktickWrapped() {
        #expect(
            AllureFormatter.legacyTestName("When A/B enabled, should show icon")
                == "`When A/B enabled, should show icon`()"
        )
    }

    @Test
    func suitePrefixFromTopLevelSuite() {
        #expect(
            AllureFormatter.suiteIdentifierPrefix(
                from: "test://com.apple.xcode/Module/ModuleTests/SuiteTests"
            ) == "SuiteTests"
        )
    }

    @Test
    func suitePrefixFromNestedSuite() {
        #expect(
            AllureFormatter.suiteIdentifierPrefix(
                from: "test://com.apple.xcode/Module/ModuleTests/OuterSuite/InnerSuite"
            ) == "OuterSuite/InnerSuite"
        )
    }

    @Test
    func suitePrefixDecodesPercentEncoding() {
        #expect(
            AllureFormatter.suiteIdentifierPrefix(
                from: "test://com.apple.xcode/Module/ModuleTests/%60Display%20suite%60"
            ) == "`Display suite`"
        )
    }

    @Test
    func suitePrefixForBundleURLIsNil() {
        #expect(
            AllureFormatter.suiteIdentifierPrefix(
                from: "test://com.apple.xcode/Module/ModuleTests"
            ) == nil
        )
    }
}
