import Foundation

/// Formats a flat collection of `(fileName, Issue)` pairs as JSON or plain text.
///
/// `peekie warnings` and `peekie errors` use this with `Report.files.flatMap(\.warnings)`
/// and `Report.files.flatMap(\.errors)` respectively. Output is intentionally schema-stable
/// across both — the only difference is which array on `File` you flatten.
public final class IssuesFormatter {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// JSON: a sorted flat array of `{file, line, column, type, message}` objects.
    /// `line` / `column` are `null` when `Issue.location` is absent.
    public func json(_ files: [Report.File], on keyPath: KeyPath<Report.File, [Report.File.Issue]>)
        throws -> String
    {
        let entries = entries(files: files, on: keyPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        return String(decoding: data, as: UTF8.self)
    }

    /// Human-readable: one `file:line:column [Type] message` per line.
    public func list(_ files: [Report.File], on keyPath: KeyPath<Report.File, [Report.File.Issue]>)
        -> String
    {
        let entries = entries(files: files, on: keyPath)
        return
            entries
                .map { entry in
                    let loc = [entry.line.map(String.init), entry.column.map(String.init)]
                        .compactMap(\.self)
                        .joined(separator: ":")
                    let prefix = loc.isEmpty ? entry.file : "\(entry.file):\(loc)"
                    return "\(prefix) [\(entry.type)] \(entry.message)"
                }
                .joined(separator: "\n")
    }

    // MARK: Private

    private struct Entry: Encodable {
        // MARK: Lifecycle

        init(file: String, issue: Report.File.Issue) {
            self.file = file
            line = issue.location?.startLine
            column = issue.location?.startColumn
            type = issue.type.rawValue
            message = issue.message
        }

        // MARK: Internal

        let file: String
        let line: Int?
        let column: Int?
        let type: String
        let message: String
    }

    private func entries(
        files: [Report.File],
        on keyPath: KeyPath<Report.File, [Report.File.Issue]>
    )
        -> [Entry]
    {
        var entries = [Entry]()
        for file in files {
            for issue in file[keyPath: keyPath] {
                entries.append(.init(file: file.name, issue: issue))
            }
        }
        return entries.sorted { lhs, rhs in
            if lhs.file != rhs.file {
                return lhs.file < rhs.file
            }
            let ll = lhs.line ?? .max
            let rl = rhs.line ?? .max
            if ll != rl {
                return ll < rl
            }
            let lc = lhs.column ?? .max
            let rc = rhs.column ?? .max
            if lc != rc {
                return lc < rc
            }
            if lhs.type != rhs.type {
                return lhs.type < rhs.type
            }
            return lhs.message < rhs.message
        }
    }
}
