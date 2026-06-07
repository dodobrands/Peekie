import ArgumentParser
import Foundation
import PeekieSDK

public struct Warnings: AsyncParsableCommand {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public enum Format: String, ExpressibleByArgument, CaseIterable {
        case json
        case list
    }

    public static let configuration = CommandConfiguration(
        commandName: "warnings",
        abstract: "Print build warnings from an .xcresult bundle"
    )

    @Argument(help: "Path to .xcresult")
    public var xcresultPath: String

    @Option(help: "Output format: json or list.")
    public var format = Format.json

    @Flag(name: .shortAndLong, help: "Enable verbose logging (debug level)")
    public var verbose = false

    public func run() async throws {
        LoggingSetup.setup(verbose: verbose)
        let xcresultPath = URL(fileURLWithPath: xcresultPath)

        let report = try await Report(
            xcresultPath: xcresultPath,
            includeCoverage: false,
            includeWarnings: true,
            includeTests: false
        )

        let formatter = IssuesFormatter()
        switch format {
        case .json:
            try print(formatter.json(report.files, flattening: \.warnings))
        case .list:
            print(formatter.list(report.files, flattening: \.warnings))
        }
    }
}
