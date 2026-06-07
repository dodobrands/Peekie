import Foundation

private enum WarningRegex {
    static let duplicate = try! NSRegularExpression(
        pattern: "(?m)^(.+?)\\r?\\n#warning\\(\"\\1\"\\)")
    static let whitespace = try! NSRegularExpression(pattern: "\\s+")
}

extension Report {
    // MARK: - Warnings Processing

    /// Parses warnings from BuildResultsDTO and returns a map of file names to their issues
    static func parseWarnings(
        from buildResultsDTO: BuildResultsDTO
    ) async -> [String: [Module.File.Issue]] {
        await parseIssues(buildResultsDTO.warnings)
    }

    /// Parses errors from BuildResultsDTO and returns a map of file names to their issues.
    /// Symmetric to ``parseWarnings(from:)``: same DTO shape, same normalization, same
    /// per-file grouping. Errors without a `sourceURL` (link errors, project-level errors)
    /// are dropped — same as warnings.
    static func parseErrors(
        from buildResultsDTO: BuildResultsDTO
    ) async -> [String: [Module.File.Issue]] {
        await parseIssues(buildResultsDTO.errors)
    }

    private static func parseIssues(
        _ dtoIssues: [BuildResultsDTO.Issue]
    ) async -> [String: [Module.File.Issue]] {
        let parsed = await dtoIssues.concurrentCompactMap {
            issue -> (String, Module.File.Issue)? in
            guard let fileName = issue.fileName else { return nil }

            let normalized = normalizeWarningMessage(issue.message)
            guard !normalized.isEmpty else { return nil }

            return (
                fileName,
                Module.File.Issue(
                    type: Module.File.Issue.IssueType(rawValue: issue.issueType),
                    message: normalized,
                    location: issue.location
                )
            )
        }

        let grouped = Dictionary(grouping: parsed, by: { $0.0 })
        return grouped.mapValues { $0.map(\.1) }
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
            .filter { !$0.hasPrefix("^") && !$0.hasPrefix("#warning(") }
            .joined(separator: "\n")

        let collapsed = WarningRegex.whitespace.stringByReplacingMatches(
            in: filtered,
            options: [],
            range: NSRange(location: 0, length: (filtered as NSString).length),
            withTemplate: " "
        )

        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Retrieves issues matching a file name, optionally trying with a `.swift` suffix
    static func issuesFor(
        fileName: String,
        in issuesByFileName: [String: [Module.File.Issue]]
    ) -> [Module.File.Issue] {
        if let issues = issuesByFileName[fileName] {
            return issues
        }
        if !fileName.hasSuffix(".swift") {
            return issuesByFileName[fileName + ".swift"] ?? []
        }
        return []
    }

    /// Concatenates two arrays of issues. The SDK no longer deduplicates — every
    /// xcresult record is surfaced; grouping/dedup is a consumer decision.
    static func mergeIssues(
        _ existing: [Module.File.Issue],
        _ new: [Module.File.Issue]
    ) -> [Module.File.Issue] {
        existing + new
    }
}
