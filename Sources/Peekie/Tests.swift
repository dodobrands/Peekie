import ArgumentParser
import Foundation
import PeekieSDK

public struct Tests: AsyncParsableCommand {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public enum Format: String, ExpressibleByArgument, CaseIterable {
        case json
        case list
        case sonar
    }

    public enum AttachmentsMode: String, ExpressibleByArgument, CaseIterable {
        case skip
        case export
    }

    public static let configuration = CommandConfiguration(
        commandName: "tests",
        abstract: "Print test results from an .xcresult bundle"
    )

    @Argument(help: "Path to .xcresult")
    public var xcresultPath: String

    @Option(help: "Output format: json, list, or sonar.")
    public var format = Format.list

    @Option(help: "Comma-separated test statuses to include (success,failure,skipped,...).")
    public var include: String = Report.Module.Suite.RepeatableTest.Test.Status.allCases
        .map(\.rawValue)
        .joined(separator: ",")

    @Option(help: "Include device information in test names (matters for matrix runs).")
    public var includeDeviceDetails = false

    @Option(help: "Path to test sources (required with --format sonar).")
    public var testsPath: String?

    @Option(help: "Attachments handling: skip (default) or export.")
    public var attachments = AttachmentsMode.skip

    @Option(
        name: .customLong("attachments-to"),
        help: "Output directory for exported attachments. Required with --attachments export."
    )
    public var attachmentsTo: String?

    @Flag(name: .shortAndLong, help: "Enable verbose logging (debug level)")
    public var verbose = false

    public func run() async throws {
        LoggingSetup.setup(verbose: verbose)
        let xcresultPath = URL(fileURLWithPath: xcresultPath)

        let attachmentsPolicy: AttachmentPolicy
        switch attachments {
        case .skip:
            attachmentsPolicy = .skip
        case .export:
            guard let attachmentsTo else {
                throw ValidationError("--attachments-to is required when --attachments export")
            }

            attachmentsPolicy = .extractTo(URL(fileURLWithPath: attachmentsTo))
        }

        let report = try await Report(
            xcresultPath: xcresultPath,
            includeCoverage: false,
            includeWarnings: false,
            includeTests: true,
            attachments: attachmentsPolicy
        )

        let statuses = include.split(separator: ",")
            .compactMap { Report.Module.Suite.RepeatableTest.Test.Status(rawValue: String($0)) }

        switch format {
        case .list:
            let formatter = PeekieSDK.ListFormatter()
            print(
                formatter.format(
                    report, include: statuses, includeDeviceDetails: includeDeviceDetails
                )
            )

        case .json:
            let formatter = PeekieSDK.JSONFormatter()
            try print(
                formatter.format(
                    report, include: statuses, includeDeviceDetails: includeDeviceDetails
                )
            )

        case .sonar:
            guard let testsPath else {
                throw ValidationError("--tests-path is required when --format sonar")
            }

            let formatter = PeekieSDK.SonarFormatter()
            try print(
                formatter.format(
                    report: report, testsPath: URL(fileURLWithPath: testsPath)
                )
            )
        }
    }
}
