import Foundation
import Logging

public class JsonFormatter {
    private let logger = Logger(label: "com.peekie.formatter.json")

    public init() {}

    public func format(
        _ report: Report,
        include: [Report.Module.Suite.RepeatableTest.Test.Status] = Report.Module
            .Suite.RepeatableTest.Test.Status.allCases,
        includeDeviceDetails: Bool = false
    ) throws -> String {
        logger.debug(
            "Formatting report as JSON",
            metadata: [
                "modulesCount": "\(report.modules.count)",
                "includeStatuses": "\(include.map { $0.rawValue }.joined(separator: ","))",
                "includeDeviceDetails": "\(includeDeviceDetails)",
            ]
        )

        let jsonReport = JsonReport(
            from: report,
            include: include,
            includeDeviceDetails: includeDeviceDetails
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(jsonReport)
        return String(decoding: data, as: UTF8.self)
    }
}

private struct JsonReport: Encodable {
    let coverage: Double?
    let modules: [JsonModule]

    init(
        from report: Report,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        includeDeviceDetails: Bool
    ) {
        self.coverage = report.coverage
        self.modules = report.modules
            .sorted { $0.name < $1.name }
            .map {
                JsonModule(
                    from: $0,
                    include: include,
                    includeDeviceDetails: includeDeviceDetails
                )
            }
    }
}

private struct JsonModule: Encodable {
    let coverage: JsonCoverage?
    let files: [JsonFile]
    let name: String
    let suites: [JsonSuite]

    init(
        from module: Report.Module,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        includeDeviceDetails: Bool
    ) {
        self.name = module.name
        self.coverage = module.coverage.map { JsonCoverage(from: $0) }
        self.files = module.files
            .sorted { $0.name < $1.name }
            .map { JsonFile(from: $0) }
        self.suites = module.suites
            .sorted { $0.name < $1.name }
            .map {
                JsonSuite(
                    from: $0,
                    include: include,
                    includeDeviceDetails: includeDeviceDetails
                )
            }
    }
}

private struct JsonCoverage: Encodable {
    let coveredLines: Int
    let percentage: Double
    let totalLines: Int

    init(from coverage: Report.Coverage) {
        self.coveredLines = coverage.coveredLines
        self.totalLines = coverage.totalLines
        self.percentage = coverage.coverage
    }

    init(from coverage: Report.Module.File.Coverage) {
        self.coveredLines = coverage.coveredLines
        self.totalLines = coverage.totalLines
        self.percentage = coverage.coverage
    }
}

private struct JsonFile: Encodable {
    let coverage: JsonCoverage?
    let name: String
    let warnings: [JsonWarning]

    init(from file: Report.Module.File) {
        self.name = file.name
        self.coverage = file.coverage.map { JsonCoverage(from: $0) }
        self.warnings = file.warnings.map { JsonWarning(from: $0) }
    }
}

private struct JsonWarning: Encodable {
    let message: String
    let type: String

    init(from issue: Report.Module.File.Issue) {
        self.type = issue.type.rawValue
        self.message = issue.message
    }
}

private struct JsonSuite: Encodable {
    let name: String
    let tests: [JsonTest]

    init(
        from suite: Report.Module.Suite,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        includeDeviceDetails: Bool
    ) {
        self.name = suite.name
        self.tests = suite.repeatableTests
            .filtered(testResults: include)
            .sorted { $0.name < $1.name }
            .flatMap { repeatableTest in
                repeatableTest.mergedTests(filterDevice: !includeDeviceDetails)
                    .filter { include.contains($0.status) }
                    .map { JsonTest(from: $0) }
            }
    }
}

private struct JsonTest: Encodable {
    let durationMs: Double
    let message: String?
    let name: String
    let status: String

    init(from test: Report.Module.Suite.RepeatableTest.Test) {
        self.name = test.name
        self.status = test.status.rawValue
        self.durationMs = test.duration.converted(to: .milliseconds).value
        self.message = test.message
    }
}
