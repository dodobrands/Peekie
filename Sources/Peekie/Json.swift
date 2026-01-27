import ArgumentParser
import Foundation
import PeekieSDK

public struct Json: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "json",
        abstract: "Format test results as JSON"
    )

    public init() {}

    @Argument(help: "Path to .xcresult")
    public var xcresultPath: String

    @Option(help: "Test statuses to include in report, comma separated")
    public var include: String = Report.Module.Suite.RepeatableTest.Test.Status.allCases.map {
        $0.rawValue
    }.joined(separator: ",")

    @Option(help: "Whether to parse and include code coverage data")
    public var includeCoverage: Bool = true

    @Option(help: "Whether to parse and include build warnings")
    public var includeWarnings: Bool = true

    @Option(help: "Include device information in test names")
    public var includeDeviceDetails: Bool = false

    @Flag(name: .shortAndLong, help: "Enable verbose logging (debug level)")
    public var verbose: Bool = false

    public func run() async throws {
        LoggingSetup.setup(verbose: verbose)
        let xcresultPath = URL(fileURLWithPath: xcresultPath)

        let report = try await Report(
            xcresultPath: xcresultPath,
            includeCoverage: includeCoverage,
            includeWarnings: includeWarnings
        )

        let include = include.split(separator: ",")
            .compactMap {
                Report.Module.Suite.RepeatableTest.Test.Status(rawValue: String($0))
            }

        let formatter = PeekieSDK.JsonFormatter()

        let result = try formatter.format(
            report,
            include: include,
            includeDeviceDetails: includeDeviceDetails
        )

        print(result)
    }
}
