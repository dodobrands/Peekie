import Foundation

/// Formats a `Report` as a coverage-only view.
///
/// Used by `peekie coverage`. Drops everything except `coverage`, `modules[].coverage`,
/// `modules[].files[].coverage`.
public final class CoverageFormatter {
    // MARK: Lifecycle

    /// Creates a new formatter.
    public init() {}

    // MARK: Public

    /// JSON: `{coverage, modules: [{name, coverage, files: [{name, path, coverage}]}]}`.
    public func json(_ report: Report) throws -> String {
        let snapshot = Snapshot(from: report)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        return String(decoding: data, as: UTF8.self)
    }

    /// Human-readable: padded table of `name pct% (covered/total)` per module + total.
    public func list(_ report: Report) -> String {
        let rows = report.modules
            .compactMap { module -> Row? in
                guard let coverage = module.coverage else {
                    return nil
                }

                return Row(
                    name: module.name,
                    coverage: coverage.coverage,
                    coveredLines: coverage.coveredLines,
                    totalLines: coverage.totalLines
                )
            }
            .sorted { $0.name < $1.name }

        let nameWidth = max(5, rows.map(\.name.count).max() ?? 0)
        let lineRows: [String] = rows.map { row in
            let pct = String(format: "%5.1f%%", row.coverage * 100)
            let paddedName = row.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            return "\(paddedName)  \(pct)  (\(row.coveredLines)/\(row.totalLines))"
        }

        var lines = lineRows
        if let total = report.coverage {
            let pct = String(format: "%5.1f%%", total * 100)
            lines.append(
                "\("total".padding(toLength: nameWidth, withPad: " ", startingAt: 0))  \(pct)"
            )
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Private

    private struct Row {
        let name: String
        let coverage: Double
        let coveredLines: Int
        let totalLines: Int
    }

    private struct Snapshot: Encodable {
        // MARK: Lifecycle

        init(from report: Report) {
            coverage = report.coverage
            modules = report.modules
                .sorted { $0.name < $1.name }
                .map(ModuleSnapshot.init)
        }

        // MARK: Internal

        let coverage: Double?
        let modules: [ModuleSnapshot]
    }

    private struct ModuleSnapshot: Encodable {
        // MARK: Lifecycle

        init(_ module: Report.Module) {
            name = module.name
            coverage = module.coverage?.coverage
            coveredLines = module.coverage?.coveredLines
            totalLines = module.coverage?.totalLines
            files = module.files
                .sorted { $0.name < $1.name }
                .compactMap { file -> FileSnapshot? in
                    guard let coverage = file.coverage else {
                        return nil
                    }

                    return .init(
                        name: file.name,
                        path: file.path,
                        coverage: coverage.coverage,
                        coveredLines: coverage.coveredLines,
                        totalLines: coverage.totalLines
                    )
                }
        }

        // MARK: Internal

        let name: String
        let coverage: Double?
        let coveredLines: Int?
        let totalLines: Int?
        let files: [FileSnapshot]
    }

    private struct FileSnapshot: Encodable {
        let name: String
        let path: String?
        let coverage: Double
        let coveredLines: Int
        let totalLines: Int
    }
}
