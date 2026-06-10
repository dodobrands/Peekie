import Foundation
import Logging

// MARK: - AttachmentsFormatter

/// Formats a `Report`'s attachments as a flat JSON array or human-readable list.
/// Used by `peekie attachments --format {json,list}`.
public final class AttachmentsFormatter {
    // MARK: Lifecycle

    /// Creates a new formatter.
    public init() {}

    // MARK: Public

    /// Encodes all attachments in `report` as a flat JSON array sorted by
    /// qualified test name and attachment name.
    /// - Parameters:
    ///   - report: The parsed report. Attachments must have been extracted via
    ///     `Report(xcresultPath:…, attachments: .extractTo(_))`.
    ///   - include: Test statuses to surface (defaults to all).
    /// - Returns: Pretty-printed JSON.
    public func json(
        _ report: Report,
        include: [Report.Module.Suite.RepeatableTest.Test.Status] = Report.Module
            .Suite.RepeatableTest.Test.Status.allCases
    ) throws
        -> String
    {
        logger.debug(
            "Formatting attachments as JSON",
            metadata: [
                "modulesCount": "\(report.modules.count)",
                "includeStatuses": "\(include.map(\.rawValue).joined(separator: ","))",
            ]
        )

        let rows = collectRows(from: report, include: include)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rows)
        return String(decoding: data, as: UTF8.self)
    }

    /// Renders attachments grouped by test, one section per test, one indented
    /// line per attachment. Tests without attachments are omitted.
    public func list(
        _ report: Report,
        include: [Report.Module.Suite.RepeatableTest.Test.Status] = Report.Module
            .Suite.RepeatableTest.Test.Status.allCases
    )
        -> String
    {
        logger.debug(
            "Formatting attachments as list",
            metadata: [
                "modulesCount": "\(report.modules.count)",
                "includeStatuses": "\(include.map(\.rawValue).joined(separator: ","))",
            ]
        )

        let rows = collectRows(from: report, include: include)
        let grouped = Dictionary(grouping: rows, by: \.qualifiedName)
        let qualifiedNames = grouped.keys.sorted()

        var lines = [String]()
        for qualifiedName in qualifiedNames {
            lines.append(qualifiedName)
            let attachments = (grouped[qualifiedName] ?? []).sorted { $0.name < $1.name }
            for attachment in attachments {
                let suffix = attachment.isAssociatedWithFailure ? "  (failure)" : ""
                lines
                    .append(
                        "  📎 \(attachment.name) — \(attachment.exportedFileName)\(suffix)"
                    )
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Private

    private let logger = Logger(label: "com.peekie.formatter.attachments")

    private func collectRows(
        from report: Report,
        include: [Report.Module.Suite.RepeatableTest.Test.Status]
    )
        -> [AttachmentRow]
    {
        var rows = [AttachmentRow]()
        for module in report.modules.sorted(by: { $0.name < $1.name }) {
            let rootLevelTests = report.rootLevelTests(in: module)
                .filtered(testResults: include)
                .flatMap { repeatableTest in
                    repeatableTest.mergedTests()
                        .filter { include.contains($0.status) }
                }
            for test in rootLevelTests {
                appendRows(
                    for: test,
                    qualifiedName: "\(module.name) / \(test.name)",
                    into: &rows
                )
            }
            for suite in report.suites(in: module) {
                collectRows(
                    from: suite,
                    modulePrefix: module.name,
                    include: include,
                    into: &rows
                )
            }
        }
        return rows.sorted { lhs, rhs in
            if lhs.qualifiedName == rhs.qualifiedName {
                return lhs.name < rhs.name
            }
            return lhs.qualifiedName < rhs.qualifiedName
        }
    }

    private func collectRows(
        from suite: Report.Module.Suite,
        modulePrefix: String,
        include: [Report.Module.Suite.RepeatableTest.Test.Status],
        into rows: inout [AttachmentRow]
    ) {
        let suitePrefix = "\(modulePrefix) / \(suite.fullPath)"
        let tests = suite.repeatableTests
            .filtered(testResults: include)
            .flatMap { repeatableTest in
                repeatableTest.mergedTests()
                    .filter { include.contains($0.status) }
            }
        for test in tests {
            appendRows(
                for: test,
                qualifiedName: "\(suitePrefix) / \(test.name)",
                into: &rows
            )
        }
        for nested in suite.nestedSuites {
            collectRows(
                from: nested,
                modulePrefix: modulePrefix,
                include: include,
                into: &rows
            )
        }
    }

    private func appendRows(
        for test: Report.Module.Suite.RepeatableTest.Test,
        qualifiedName: String,
        into rows: inout [AttachmentRow]
    ) {
        for attachment in test.attachments {
            rows.append(AttachmentRow(qualifiedName: qualifiedName, attachment: attachment))
        }
    }
}

// MARK: - AttachmentRow

/// One flat row in the attachments output: identifies the owning test by its
/// qualified name and embeds the attachment metadata. The shape is shared
/// between `peekie attachments --format json` and the JSON nested under
/// per-test entries in `peekie tests --format json --attachments export`.
private struct AttachmentRow: Encodable {
    // MARK: Lifecycle

    init(qualifiedName: String, attachment: Report.Module.Suite.RepeatableTest.Test.Attachment) {
        self.qualifiedName = qualifiedName
        name = attachment.name
        exportedFileName = attachment.exportedFileName
        path = attachment.path.path
        contentType = attachment.contentType
        isAssociatedWithFailure = attachment.isAssociatedWithFailure
        repetitionNumber = attachment.repetitionNumber
        deviceID = attachment.deviceID
        configurationName = attachment.configurationName
    }

    // MARK: Internal

    let configurationName: String?
    let contentType: String?
    let deviceID: String?
    let exportedFileName: String
    let isAssociatedWithFailure: Bool
    let name: String
    let path: String
    let qualifiedName: String
    let repetitionNumber: Int?
}
