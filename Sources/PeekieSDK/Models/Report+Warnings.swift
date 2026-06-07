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
        let parsed = await buildResultsDTO.warnings.concurrentCompactMap {
            warning -> (String, Module.File.Issue)? in
            guard let fileName = warning.fileName else { return nil }

            let normalized = normalizeWarningMessage(warning.message)
            guard !normalized.isEmpty else { return nil }

            return (
                fileName,
                Module.File.Issue(
                    type: Module.File.Issue.IssueType(rawValue: warning.issueType),
                    message: normalized,
                    location: warning.location
                )
            )
        }

        let grouped = Dictionary(grouping: parsed, by: { $0.0 })
        return grouped.mapValues { pairs in
            var seen = Set<String>()
            return pairs.compactMap { _, issue in
                guard seen.insert(issue.message).inserted else { return nil }
                return issue
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

    /// Retrieves warnings matching a file name, optionally trying with a `.swift` suffix
    static func warningsFor(
        fileName: String,
        in warningsByFileName: [String: [Module.File.Issue]]
    ) -> [Module.File.Issue] {
        if let warnings = warningsByFileName[fileName] {
            return warnings
        }
        if !fileName.hasSuffix(".swift") {
            return warningsByFileName[fileName + ".swift"] ?? []
        }
        return []
    }

    /// Merges two arrays of warnings, removing duplicates based on message content
    static func mergeWarnings(
        _ existing: [Module.File.Issue],
        _ new: [Module.File.Issue]
    ) -> [Module.File.Issue] {
        guard !new.isEmpty else { return existing }
        var combined = existing
        // Use normalized messages for comparison since warnings are already normalized
        let existingMessages = Set(combined.map { $0.message })
        for warning in new where !existingMessages.contains(warning.message) {
            combined.append(warning)
        }
        return combined
    }
}
