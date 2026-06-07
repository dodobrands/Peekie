import Foundation

// MARK: - WarningRegex

private enum WarningRegex {
    static let duplicate = try! NSRegularExpression(
        pattern: "(?m)^(.+?)\\r?\\n#warning\\(\"\\1\"\\)"
    )
    static let whitespace = try! NSRegularExpression(pattern: "\\s+")
}

extension Report {
    // MARK: - Warnings Processing

    /// Parses warnings from BuildResultsDTO and returns a map of file names to their issues
    static func parseWarnings(
        from buildResultsDTO: BuildResultsDTO
    ) async
        -> [String: [File.Issue]]
    {
        await parseIssues(buildResultsDTO.warnings)
    }

    /// Parses errors from BuildResultsDTO and returns a map of file names to their issues.
    /// Symmetric to ``parseWarnings(from:)``: same DTO shape, same normalization, same
    /// per-file grouping. Errors without a `sourceURL` (link errors, project-level errors)
    /// are dropped — same as warnings.
    static func parseErrors(
        from buildResultsDTO: BuildResultsDTO
    ) async
        -> [String: [File.Issue]]
    {
        await parseIssues(buildResultsDTO.errors)
    }

    private static func parseIssues(
        _ dtoIssues: [BuildResultsDTO.Issue]
    ) async
        -> [String: [File.Issue]]
    {
        let parsed = await dtoIssues.concurrentCompactMap {
            issue -> (String, File.Issue)? in
            guard let fileName = issue.fileName else {
                return nil
            }

            let normalized = normalizeWarningMessage(issue.message)
            guard normalized.isEmpty == false else {
                return nil
            }

            return (
                fileName,
                File.Issue(
                    type: File.Issue.IssueType(rawValue: issue.issueType),
                    message: normalized,
                    location: issue.location
                )
            )
        }

        let grouped = Dictionary(grouping: parsed, by: { $0.0 })
        // Sort issues within each file deterministically — concurrentCompactMap
        // doesn't guarantee order, and snapshot tests are sensitive to it.
        return grouped.mapValues { pairs in
            pairs.map(\.1).sorted { lhs, rhs in
                let lhsLine = lhs.location?.startLine ?? .max
                let rhsLine = rhs.location?.startLine ?? .max
                if lhsLine != rhsLine {
                    return lhsLine < rhsLine
                }
                let lhsCol = lhs.location?.startColumn ?? .max
                let rhsCol = rhs.location?.startColumn ?? .max
                if lhsCol != rhsCol {
                    return lhsCol < rhsCol
                }
                if lhs.type.rawValue != rhs.type.rawValue {
                    return lhs.type.rawValue < rhs.type.rawValue
                }
                return lhs.message < rhs.message
            }
        }
    }

    /// Normalizes a warning message by removing duplicate patterns and cleaning up formatting
    static func normalizeWarningMessage(_ message: String) -> String {
        let duplicateWarningRemoved = WarningRegex.duplicate.stringByReplacingMatches(
            in: message,
            options: [],
            range: NSRange(location: 0, length: (message as NSString).length),
            withTemplate: "$1"
        )

        let filtered =
            duplicateWarningRemoved
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("^") == false && $0.hasPrefix("#warning(") == false }
                .joined(separator: "\n")

        let collapsed = WarningRegex.whitespace.stringByReplacingMatches(
            in: filtered,
            options: [],
            range: NSRange(location: 0, length: (filtered as NSString).length),
            withTemplate: " "
        )

        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
