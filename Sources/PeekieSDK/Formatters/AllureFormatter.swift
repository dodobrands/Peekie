import Foundation

// MARK: - AllureTestResult

/// A single Allure 2 test result, one `<uuid>-result.json` file worth of data.
///
/// Field set follows the [Allure 2 result
/// schema](https://allurereport.org/docs/how-it-works-test-result-file/)
/// as produced by the de-facto standard xcresult exporter
/// [eroshenkoam/xcresults](https://github.com/eroshenkoam/xcresults), so migrating
/// to Peekie preserves test identity in Allure TestOps:
/// - `fullName` is the legacy xcresult test identifier, e.g. ``Suite/`display name`()``;
/// - `historyId` is `<target>/<fullName>`;
/// - a result is emitted per execution (repetition × device × arguments), and executions
///   of one test are chained on the timeline so retry resolution picks the final attempt.
public struct AllureTestResult: Encodable {
    // MARK: Public

    public struct Label: Encodable {
        public let name: String
        public let value: String
    }

    public struct Parameter: Encodable {
        public let name: String
        public let value: String
    }

    public struct StatusDetails: Encodable {
        public let message: String
    }

    public struct Attachment: Encodable {
        // MARK: Public

        /// Human-readable attachment name as set in test code.
        public let name: String

        /// File name inside the allure-results directory (`<uuid>-attachment.<ext>`).
        public let source: String

        /// MIME type when known.
        public let type: String?

        // MARK: Internal

        enum CodingKeys: String, CodingKey {
            case name
            case source
            case type
        }

        /// Where the exported file currently lives on disk; used by
        /// ``AllureFormatter/write(report:to:startedAt:makeUUID:)`` to copy the
        /// file next to the result JSONs. Not part of the Allure schema.
        let originalPath: URL
    }

    public let uuid: String
    public let historyID: String
    public let fullName: String
    public let name: String
    public let status: String
    public let stage: String
    public let start: Int
    public let stop: Int
    public let labels: [Label]
    public let parameters: [Parameter]
    public let statusDetails: StatusDetails?
    public let attachments: [Attachment]

    // MARK: Internal

    /// The Allure 2 schema spells the key `historyId`; the property follows
    /// Swift acronym casing, so the mapping is explicit.
    enum CodingKeys: String, CodingKey {
        case uuid
        case historyID = "historyId"
        case fullName
        case name
        case status
        case stage
        case start
        case stop
        case labels
        case parameters
        case statusDetails
        case attachments
    }
}

// MARK: - AllureFormatter

/// Formatter that emits test results in Allure 2 format.
///
/// The produced directory is ready for `allurectl upload` (Allure TestOps) or
/// `allure generate` (Allure Report): one `<uuid>-result.json` per test execution
/// plus attachment files referenced from the results.
///
/// Unlike exporters built on the legacy `xcresulttool get object` API (one process
/// per test — minutes on large bundles), this formatter reuses the already-parsed
/// ``Report``, so the only cost on top of `Report(xcresultPath:)` is writing files.
public final class AllureFormatter {
    // MARK: Lifecycle

    /// Creates a new Allure formatter instance.
    public init() {}

    // MARK: Public

    /// Totals of a completed ``write(report:to:startedAt:makeUUID:)`` call.
    public struct WriteSummary {
        /// Number of result files written, keyed by Allure status.
        public let resultCountsByStatus: [String: Int]

        /// Total number of result files written.
        public let resultsTotal: Int

        /// Total number of attachment files copied.
        public let attachmentsTotal: Int
    }

    /// Builds Allure results from a report. Pure transform: deterministic given
    /// `startedAt` and `makeUUID`.
    ///
    /// Executions of one test are chained back-to-back starting at `startedAt`
    /// so that consumers resolving retries by the latest `stop` (Allure TestOps,
    /// Allure Report) pick the final attempt — the same order real per-attempt
    /// timestamps would produce.
    ///
    /// - Parameters:
    ///   - report: Parsed report; build it with `attachments: .extractTo(_)` if
    ///     attachment files should be referenced.
    ///   - startedAt: Timeline origin for the emitted results.
    ///   - makeUUID: UUID source; inject a deterministic one in tests.
    public func results(
        report: Report,
        startedAt: Date,
        makeUUID: () -> UUID = UUID.init
    )
        -> [AllureTestResult]
    {
        var results = [AllureTestResult]()
        let baseStartMs = Int((startedAt.timeIntervalSince1970 * 1000).rounded())

        for module in report.modules.sorted(by: { $0.name < $1.name }) {
            let suites = report.suites(in: module).flatMap { Self.flatten($0) }
            for suite in suites.sorted(by: { $0.fullPath < $1.fullPath }) {
                let prefix = Self.suiteIdentifierPrefix(from: suite.nodeIdentifierURL)
                for repeatableTest in suite.repeatableTests.sorted(by: { $0.name < $1.name }) {
                    append(
                        repeatableTest,
                        module: module,
                        suitePrefix: prefix,
                        baseStartMs: baseStartMs,
                        makeUUID: makeUUID,
                        into: &results
                    )
                }
            }

            let rootLevelTests = report.rootLevelTests(in: module)
            for repeatableTest in rootLevelTests.sorted(by: { $0.name < $1.name }) {
                append(
                    repeatableTest,
                    module: module,
                    suitePrefix: nil,
                    baseStartMs: baseStartMs,
                    makeUUID: makeUUID,
                    into: &results
                )
            }
        }

        return results
    }

    /// Writes Allure results and their attachment files into `outputDirectory`,
    /// creating it when missing.
    @discardableResult
    public func write(
        report: Report,
        to outputDirectory: URL,
        startedAt: Date = Date(),
        makeUUID: () -> UUID = UUID.init
    ) throws
        -> WriteSummary
    {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let items = results(report: report, startedAt: startedAt, makeUUID: makeUUID)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        var countsByStatus = [String: Int]()
        var attachmentsTotal = 0

        for item in items {
            countsByStatus[item.status, default: 0] += 1

            for attachment in item.attachments {
                let destination = outputDirectory.appendingPathComponent(attachment.source)
                do {
                    try fileManager.copyItem(at: attachment.originalPath, to: destination)
                    attachmentsTotal += 1
                } catch {
                    // A missing attachment file should not sink the whole export:
                    // results are the valuable part, attachments are extras.
                    continue
                }
            }

            let fileURL = outputDirectory.appendingPathComponent("\(item.uuid)-result.json")
            try encoder.encode(item).write(to: fileURL)
        }

        return WriteSummary(
            resultCountsByStatus: countsByStatus,
            resultsTotal: items.count,
            attachmentsTotal: attachmentsTotal
        )
    }

    // MARK: Internal

    /// Last component of a test identifier — the test's own name without the
    /// suite path. A `/` inside backticks is part of a Swift Testing display
    /// name, not a path separator: ``Suite/`When A/B enabled`()`` →
    /// `` `When A/B enabled`() ``.
    static func testName(fromIdentifier identifier: String) -> String {
        var insideBackticks = false
        var lastSlash: String.Index?
        var index = identifier.startIndex
        while index < identifier.endIndex {
            let character = identifier[index]
            if character == "`" {
                insideBackticks.toggle()
            } else if character == "/", insideBackticks == false {
                lastSlash = index
            }
            index = identifier.index(after: index)
        }
        guard let slash = lastSlash else {
            return identifier
        }

        return String(identifier[identifier.index(after: slash)...])
    }

    /// Fallback legacy identifier component built from a display name, for
    /// reports parsed before `nodeIdentifier` was captured (e.g. constructed
    /// in tests via helpers).
    ///
    /// Plain function references (`test_example()`, `someTest()`) are already in
    /// legacy form. Swift Testing display names are backtick-wrapped with a `()`
    /// suffix — `` `Given A/B, then works`() `` — matching `nodeIdentifier` as
    /// emitted by `xcresulttool`. Parameterized tests cannot be reconstructed
    /// this way (their identifier is the function signature), which is exactly
    /// why ``Report/Module/Suite/RepeatableTest/nodeIdentifier`` exists.
    static func legacyTestName(_ name: String) -> String {
        if isPlainFunctionName(name) {
            return name
        }
        return "`\(name)`()"
    }

    /// Suite path prefix of the legacy test identifier, extracted from the suite's
    /// `nodeIdentifierURL`.
    ///
    /// `test://com.apple.xcode/<Module>/<Bundle>/<Outer>/<Inner>` → `Outer/Inner`.
    /// Components are split on the raw URL before percent-decoding, so decoded
    /// names containing `/` don't break the structure.
    static func suiteIdentifierPrefix(from nodeIdentifierURL: String) -> String? {
        let scheme = "test://com.apple.xcode/"
        guard nodeIdentifierURL.hasPrefix(scheme) else {
            return nil
        }

        let rawComponents = nodeIdentifierURL.dropFirst(scheme.count)
            .components(separatedBy: "/")
        guard rawComponents.count > 2 else {
            return nil
        }

        return rawComponents.dropFirst(2)
            .map { $0.removingPercentEncoding ?? $0 }
            .joined(separator: "/")
    }

    // MARK: Private

    private static func flatten(_ suite: Report.Module.Suite) -> [Report.Module.Suite] {
        [suite] + suite.nestedSuites.flatMap { flatten($0) }
    }

    private static func isPlainFunctionName(_ name: String) -> Bool {
        guard name.hasSuffix("()") else {
            return false
        }

        let base = name.dropLast(2)
        return base.isEmpty == false
            && base.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func allureStatus(
        _ status: Report.Module.Suite.RepeatableTest.Test.Status
    )
        -> String
    {
        switch status {
        case .success, .expectedFailure:
            "passed"
        case .failure, .mixed:
            "failed"
        case .skipped:
            "skipped"
        case .unknown:
            "unknown"
        }
    }

    private func append(
        _ repeatableTest: Report.Module.Suite.RepeatableTest,
        module: Report.Module,
        suitePrefix: String?,
        baseStartMs: Int,
        makeUUID: () -> UUID,
        into results: inout [AllureTestResult]
    ) {
        let fullName: String
        if let identifier = repeatableTest.nodeIdentifier {
            fullName = identifier
        } else {
            let testName = Self.legacyTestName(repeatableTest.name)
            fullName = suitePrefix.map { "\($0)/\(testName)" } ?? testName
        }
        let name = Self.testName(fromIdentifier: fullName)
        let historyID = "\(module.name)/\(fullName)"

        // Executions run back-to-back on the timeline; see `results(report:...)`.
        var cursor = baseStartMs
        for test in repeatableTest.tests {
            let durationMs = Int(test.duration.converted(to: .milliseconds).value.rounded())
            let start = cursor
            let stop = start + durationMs
            cursor = stop + 1

            var labels = [AllureTestResult.Label(name: "suite", value: module.name)]
            if let device = test.path.first(where: { $0.type == .device }) {
                labels.append(.init(name: "runDestination", value: device.name))
            }

            let parameters = test.path
                .filter { $0.type == .arguments }
                .map { AllureTestResult.Parameter(name: "arguments", value: $0.name) }

            let attachments = test.attachments.map { attachment in
                let fileExtension = (attachment.exportedFileName as NSString).pathExtension
                let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
                return AllureTestResult.Attachment(
                    name: attachment.name,
                    source: "\(makeUUID().uuidString.lowercased())-attachment\(suffix)",
                    type: attachment.contentType,
                    originalPath: attachment.path
                )
            }

            results.append(
                AllureTestResult(
                    uuid: makeUUID().uuidString.lowercased(),
                    historyID: historyID,
                    fullName: fullName,
                    name: name,
                    status: Self.allureStatus(test.status),
                    stage: "finished",
                    start: start,
                    stop: stop,
                    labels: labels,
                    parameters: parameters,
                    statusDetails: test.message.map { .init(message: $0) },
                    attachments: attachments
                )
            )
        }
    }
}
