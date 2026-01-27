import ArgumentParser
import Foundation
import Logging

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

@main
public struct Peekie: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "peekie",
        abstract: "Parse and format Xcode .xcresult files",
        subcommands: [List.self, Sonar.self, Json.self]
    )

    public init() {}
}
