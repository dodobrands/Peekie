import ArgumentParser
import Foundation
import PeekieSDK

public struct Attachments: AsyncParsableCommand {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public enum Format: String, ExpressibleByArgument, CaseIterable {
        case json
        case list
    }

    public static let configuration = CommandConfiguration(
        commandName: "attachments",
        abstract: "Export and inspect test attachments from an .xcresult bundle"
    )

    @Argument(help: "Path to .xcresult")
    public var xcresultPath: String

    @Option(name: .customLong("output-dir"), help: "Directory to extract attachments into.")
    public var outputDir: String

    @Option(name: .customLong("test-id"), help: "Limit export to a single test identifier or URL.")
    public var testID: String?

    @Option(help: "Comma-separated test statuses to include (success,failure,skipped,...).")
    public var include: String = Report.Module.Suite.RepeatableTest.Test.Status.allCases
        .map(\.rawValue)
        .joined(separator: ",")

    @Option(help: "Output format: json or list.")
    public var format = Format.json

    @Flag(name: .shortAndLong, help: "Enable verbose logging (debug level)")
    public var verbose = false

    public func run() async throws {
        LoggingSetup.setup(verbose: verbose)
        let xcresultURL = URL(fileURLWithPath: xcresultPath)
        let outputURL = URL(fileURLWithPath: outputDir)

        let statuses = include.split(separator: ",")
            .compactMap { Report.Module.Suite.RepeatableTest.Test.Status(rawValue: String($0)) }

        let report = try await Report(
            xcresultPath: xcresultURL,
            includeCoverage: false,
            includeWarnings: false,
            includeTests: true,
            attachments: .extractTo(outputURL, testID: testID)
        )

        let formatter = AttachmentsFormatter()
        switch format {
        case .json:
            try print(formatter.json(report, include: statuses))
        case .list:
            print(formatter.list(report, include: statuses))
        }
    }
}
