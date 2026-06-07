import ArgumentParser
import Foundation
import Logging

// MARK: - LoggingSetup

enum LoggingSetup {
    static func setup(verbose: Bool) {
        let logLevel: Logger.Level = verbose ? .debug : .info

        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = logLevel
            return handler
        }
    }
}

// MARK: - Peekie

@main
public struct Peekie: AsyncParsableCommand {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public static let configuration: CommandConfiguration = .init(
        commandName: "peekie",
        abstract: "Parse and format Xcode .xcresult files",
        subcommands: [Tests.self, Warnings.self, Errors.self, Coverage.self]
    )
}
