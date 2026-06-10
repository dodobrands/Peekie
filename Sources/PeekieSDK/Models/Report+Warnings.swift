import Foundation

// MARK: - WarningRegex

// Regex literals (Swift 5.7+) are compile-time-validated. Kept as local lets
// instead of static lets because `Regex<…>` isn't `Sendable` under Swift 6
// strict concurrency.

extension Report {
    // MARK: - Warnings Processing

    /// Parses warnings from BuildResultsDTO and returns a map of file names to their issues
    static func parseWarnings(
        from buildResultsDTO: BuildResultsDTO
    ) async
        -> [String: [File.Issue]]
    {
        await parseIssues(buildResultsDTO.warnings, severity: .warning)
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
        await parseIssues(buildResultsDTO.errors, severity: .error)
    }

    /// Severity of the source bucket an `[BuildResultsDTO.Issue]` was drawn from.
    /// Used by ``parseIssues(_:severity:)`` to pick the surviving record when
    /// xcresulttool double-emits a diagnostic with two `issueType` values (see
    /// ``dedupTwins(_:preferring:)`` for the policy).
    enum IssueSeverity {
        case warning
        case error
    }

    private static func parseIssues(
        _ dtoIssues: [BuildResultsDTO.Issue],
        severity: IssueSeverity
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

        let preferredType: File.Issue.IssueType = severity == .warning
            ? .swiftCompilerWarning
            : .swiftCompilerError

        let grouped = Dictionary(grouping: parsed) { $0.0 }
        // Sort issues within each file deterministically — concurrentCompactMap
        // doesn't guarantee order, and snapshot tests are sensitive to it.
        return grouped.mapValues { pairs in
            let sorted = pairs.map(\.1).sorted { lhs, rhs in
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
            return dedupTwins(sorted, preferring: preferredType)
        }
    }

    /// Collapses pairs of `Issue`s that share `(location, message)` — Apple's
    /// xcresulttool emits a `#warning("…")` (and friends) twice in the same
    /// bucket, once with `issueType: "Swift Compiler Error"` and once with
    /// `"Swift Compiler Warning"`. The two records have identical full
    /// `Location` (start/end line + column) and, after
    /// `normalizeWarningMessage`, identical `message` — differing only in
    /// `issueType`.
    ///
    /// When a key collides, the surviving record is the one whose `type`
    /// matches `preferredType` (typically the issue type that matches the
    /// bucket severity — `.swiftCompilerWarning` inside `warnings[]`,
    /// `.swiftCompilerError` inside `errors[]`). If neither side matches —
    /// or both do — the first-seen record wins (sort order is already
    /// deterministic).
    ///
    /// Records with `location == nil` are not eligible for dedup: without a
    /// source location we have no spatial proof that two `nil`-located
    /// diagnostics describe the same underlying record. They pass through.
    ///
    /// Unlike `#174` (which dropped a per-`message` dedup), this collapse
    /// keys on **full** `Location`. The `#174` regression case — the same
    /// `'oldFoo() is deprecated'` message on lines 4, 5, 12 — keeps all three
    /// records because their `startLine` values differ.
    private static func dedupTwins(
        _ issues: [File.Issue],
        preferring preferredType: File.Issue.IssueType
    )
        -> [File.Issue]
    {
        var result = [File.Issue]()
        var indexByKey = [TwinKey: Int]()
        for issue in issues {
            guard let loc = issue.location else {
                result.append(issue)
                continue
            }

            let key = TwinKey(
                startLine: loc.startLine,
                startColumn: loc.startColumn,
                endLine: loc.endLine,
                endColumn: loc.endColumn,
                message: issue.message
            )
            if let existingIdx = indexByKey[key] {
                let existing = result[existingIdx]
                if existing.type != preferredType, issue.type == preferredType {
                    result[existingIdx] = issue
                }
            } else {
                indexByKey[key] = result.count
                result.append(issue)
            }
        }
        return result
    }

    /// Hashable key for ``dedupTwins(_:preferring:)`` covering the four
    /// `Location` coordinates plus the normalized message. Path is implicit:
    /// this struct is keyed inside `mapValues` over a per-file group.
    private struct TwinKey: Hashable {
        let startLine: Int
        let startColumn: Int?
        let endLine: Int?
        let endColumn: Int?
        let message: String
    }

    /// Normalizes a warning message by removing duplicate patterns and cleaning up formatting
    static func normalizeWarningMessage(_ message: String) -> String {
        // `#warning("…")` directives produce a record whose message body
        // repeats the directive echo on the next line — strip the echo.
        let duplicateRegex = #/(?m)^(.+?)\r?\n#warning\("\1"\)/#
        let duplicateWarningRemoved = message.replacing(duplicateRegex) { match in
            String(match.output.1)
        }

        let filtered =
            duplicateWarningRemoved
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("^") == false && $0.hasPrefix("#warning(") == false }
                .joined(separator: "\n")

        let collapsed = filtered.replacing(#/\s+/#, with: " ")

        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
