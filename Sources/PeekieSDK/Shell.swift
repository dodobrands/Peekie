import Foundation
import Logging
import Subprocess

// MARK: - Shell

enum Shell {
    // MARK: Internal

    /// Runs `executable` with `arguments` and returns stdout as raw bytes.
    ///
    /// Uses `.bytes(limit: .max)` so stdout is delivered as `[UInt8]` and wrapped
    /// in `Data`, never materialized as a Swift `String`. The previous
    /// `.string(limit: .max)` path decoded every byte through `LazyMapSequence`
    /// → metadata-cache lookups, which dominated wall-clock on the multi-hundred-MB
    /// JSON `xcresulttool`/`xccov` emit on real `.xcresult` bundles.
    ///
    /// stderr stays a `String` — it's small and surfaced in `ShellError`.
    @discardableResult
    static func execute(_ executable: String, arguments: [String] = []) async throws -> Data {
        logger.debug(
            "Executing command",
            metadata: [
                "executable": "\(executable)",
                "arguments": "\(arguments.joined(separator: " "))",
            ]
        )

        let result = try await run(
            .name(executable),
            arguments: .init(arguments),
            output: .bytes(limit: .max),
            error: .string(limit: .max)
        )

        // Check if process exited successfully
        guard case .exited(let code) = result.terminationStatus, code == 0 else {
            let errorOutput = result.standardError ?? ""
            let exitCode =
                if case .exited(let exitCodeValue) = result.terminationStatus {
                    "\(exitCodeValue)"
                } else {
                    "\(result.terminationStatus)"
                }
            logger.debug(
                "Command failed",
                metadata: [
                    "executable": "\(executable)",
                    "exitCode": "\(exitCode)",
                    "error": "\(errorOutput.prefix(200))",
                ]
            )
            throw ShellError.processFailed(exitCode: result.terminationStatus, error: errorOutput)
        }

        let data = Data(result.standardOutput)
        logger.debug(
            "Command completed successfully",
            metadata: [
                "executable": "\(executable)",
                "outputLength": "\(data.count)",
            ]
        )
        return data
    }

    // MARK: Private

    private static let logger = Logger(label: "com.peekie.shell")
}

// MARK: - ShellError

enum ShellError: Error {
    case processFailed(exitCode: TerminationStatus, error: String)
}
