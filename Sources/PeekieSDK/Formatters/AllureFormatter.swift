import Foundation

// MARK: - AllureFormatter

/// Formatter that emits test results in Allure 2 format.
///
/// The produced directory is ready for `allurectl upload` (Allure TestOps) or
/// `allure generate` (Allure Report): one `<uuid>-result.json` per test execution
/// plus attachment files referenced from the results.
///
/// Unlike exporters built on the legacy `xcresulttool get object` API (one process
/// per test — minutes on large bundles), this formatter reuses the already-parsed
/// ``Report``. The `stepsFrom` variants additionally read per-test activity trees
/// (`xcresulttool get test-results activities`) and map them to Allure steps,
/// labels (`allure.label.<name>:<value>`, `allure.id:<value>`), name and
/// description overrides — one cheap call per test, worthwhile for UI test
/// bundles where the step log is the report's main content.
public final class AllureFormatter {
    // MARK: Lifecycle

    /// Creates a new Allure formatter instance.
    public init() {}

    // MARK: Public

    /// Totals of a completed `write` call.
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
    /// Without activity data there are no per-attempt timestamps, so executions
    /// of one test are chained back-to-back starting at `startedAt` — consumers
    /// resolving retries by the latest `stop` (Allure TestOps, Allure Report)
    /// then pick the final attempt, the same order real timestamps would produce.
    ///
    /// - Parameters:
    ///   - report: Parsed report; build it with `attachments: .extractTo(_)` if
    ///     attachment files should be referenced.
    ///   - startedAt: Timeline origin for the emitted results.
    ///   - makeUUID: UUID source; inject a deterministic one in tests.
    public func results(
        report: Report,
        startedAt: Date,
        makeUUID: @escaping () -> UUID = UUID.init
    )
        -> [AllureTestResult]
    {
        makeResults(
            report: report,
            startedAt: startedAt,
            activitiesByIdentifier: [:],
            makeUUID: makeUUID
        )
    }

    /// Builds Allure results with steps: reads the activity tree of every test
    /// from the bundle and maps it to Allure steps and metadata labels. Attempt
    /// timestamps come from the activities, so retries carry real times.
    public func results(
        report: Report,
        startedAt: Date,
        stepsFrom xcresultPath: URL,
        makeUUID: @escaping () -> UUID = UUID.init
    ) async
        -> [AllureTestResult]
    {
        let activities = await loadActivities(report: report, xcresultPath: xcresultPath)
        return makeResults(
            report: report,
            startedAt: startedAt,
            activitiesByIdentifier: activities,
            makeUUID: makeUUID
        )
    }

    /// Writes Allure results and their attachment files into `outputDirectory`,
    /// creating it when missing.
    @discardableResult
    public func write(
        report: Report,
        to outputDirectory: URL,
        startedAt: Date = Date(),
        makeUUID: @escaping () -> UUID = UUID.init
    ) throws
        -> WriteSummary
    {
        try write(
            items: results(report: report, startedAt: startedAt, makeUUID: makeUUID),
            to: outputDirectory
        )
    }

    /// Writes Allure results with steps — see ``results(report:startedAt:stepsFrom:makeUUID:)``.
    @discardableResult
    public func write(
        report: Report,
        to outputDirectory: URL,
        stepsFrom xcresultPath: URL,
        startedAt: Date = Date(),
        makeUUID: @escaping () -> UUID = UUID.init
    ) async throws
        -> WriteSummary
    {
        try await write(
            items: results(
                report: report,
                startedAt: startedAt,
                stepsFrom: xcresultPath,
                makeUUID: makeUUID
            ),
            to: outputDirectory
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

    static func flatten(_ suite: Report.Module.Suite) -> [Report.Module.Suite] {
        [suite] + suite.nestedSuites.flatMap { flatten($0) }
    }

    // MARK: Private

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

    private func write(items: [AllureTestResult], to outputDirectory: URL) throws -> WriteSummary {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        var countsByStatus = [String: Int]()
        var attachmentsTotal = 0

        for item in items {
            countsByStatus[item.status, default: 0] += 1

            for attachment in item.allAttachments {
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

    private func makeResults(
        report: Report,
        startedAt: Date,
        activitiesByIdentifier: [String: TestActivitiesDTO],
        makeUUID: @escaping () -> UUID
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
                        context: EmitContext(
                            module: module,
                            suitePrefix: prefix,
                            activities: repeatableTest.nodeIdentifier
                                .flatMap { activitiesByIdentifier[$0] },
                            baseStartMs: baseStartMs,
                            makeUUID: makeUUID
                        ),
                        into: &results
                    )
                }
            }

            let rootLevelTests = report.rootLevelTests(in: module)
            for repeatableTest in rootLevelTests.sorted(by: { $0.name < $1.name }) {
                append(
                    repeatableTest,
                    context: EmitContext(
                        module: module,
                        suitePrefix: nil,
                        activities: repeatableTest.nodeIdentifier
                            .flatMap { activitiesByIdentifier[$0] },
                        baseStartMs: baseStartMs,
                        makeUUID: makeUUID
                    ),
                    into: &results
                )
            }
        }

        return results
    }
}

// MARK: - Emitting

private extension AllureFormatter {
    /// Everything one test needs to be emitted: its target, suite identifier
    /// prefix, optional activity trees and the timeline origin.
    struct EmitContext {
        let module: Report.Module
        let suitePrefix: String?
        let activities: TestActivitiesDTO?
        let baseStartMs: Int
        let makeUUID: () -> UUID
    }

    func append(
        _ repeatableTest: Report.Module.Suite.RepeatableTest,
        context: EmitContext,
        into results: inout [AllureTestResult]
    ) {
        let module = context.module
        let activities = context.activities
        let makeUUID = context.makeUUID

        let fullName: String
        if let identifier = repeatableTest.nodeIdentifier {
            fullName = identifier
        } else {
            let testName = Self.legacyTestName(repeatableTest.name)
            fullName = context.suitePrefix.map { "\($0)/\(testName)" } ?? testName
        }
        let defaultName = Self.testName(fromIdentifier: fullName)
        let historyID = "\(module.name)/\(fullName)"

        // Without real timestamps the executions run back-to-back on the
        // timeline; see `results(report:startedAt:makeUUID:)`.
        var chainCursorMs = context.baseStartMs
        for (index, test) in repeatableTest.tests.enumerated() {
            let durationMs = Int(test.duration.converted(to: .milliseconds).value.rounded())
            let runActivities = activities?.testRuns[safe: index]?.activities ?? []

            let realStartMs = runActivities.first?.startTime.map { Int(($0 * 1000).rounded()) }
            let start = realStartMs ?? chainCursorMs
            let stop = start + durationMs
            chainCursorMs = stop + 1

            var builder = StepsBuilder(testAttachments: test.attachments, makeUUID: makeUUID)
            let steps = builder.makeSteps(runActivities, runStopMs: stop)

            var labels = [AllureTestResult.Label(name: "suite", value: module.name)]
            if let device = test.path.first(where: { $0.type == .device }) {
                labels.append(.init(name: "runDestination", value: device.name))
            }
            labels.append(contentsOf: builder.metadata.labels)

            let parameters = test.path
                .filter { $0.type == .arguments }
                .map { AllureTestResult.Parameter(name: "arguments", value: $0.name) }

            results.append(
                AllureTestResult(
                    uuid: makeUUID().uuidString.lowercased(),
                    historyID: historyID,
                    fullName: fullName,
                    name: builder.metadata.nameOverride ?? defaultName,
                    status: Self.allureStatus(test.status),
                    stage: "finished",
                    start: start,
                    stop: stop,
                    description: builder.metadata.description,
                    labels: labels,
                    parameters: parameters,
                    statusDetails: test.message.map { .init(message: $0) },
                    steps: steps,
                    attachments: builder.resultAttachments + builder.unclaimedAttachments
                )
            )
        }
    }
}

// MARK: - Collection Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
