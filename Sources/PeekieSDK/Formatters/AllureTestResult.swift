import Foundation

// MARK: - AllureTestResult

/// A single Allure 2 test result, one `<uuid>-result.json` file worth of data.
///
/// Field set follows the [Allure 2 result
/// schema](https://allurereport.org/docs/how-it-works-test-result-file/)
/// as produced by the de-facto standard xcresult exporter
/// [eroshenkoam/xcresults](https://github.com/eroshenkoam/xcresults), so migrating
/// to Peekie preserves test identity in Allure TestOps:
/// - `fullName` is the legacy xcresult test identifier, e.g. ``Suite/`display name`()``;
/// - `historyId` is `<target>/<fullName>`;
/// - a result is emitted per execution (repetition × device × arguments), and executions
///   of one test are ordered on the timeline so retry resolution picks the final attempt.
public struct AllureTestResult: Encodable {
    // MARK: Public

    public struct Label: Encodable {
        public let name: String
        public let value: String
    }

    public struct Parameter: Encodable {
        public let name: String
        public let value: String
    }

    public struct StatusDetails: Encodable {
        public let message: String
    }

    public struct Attachment: Encodable {
        // MARK: Public

        /// Human-readable attachment name as set in test code.
        public let name: String

        /// File name inside the allure-results directory (`<uuid>-attachment.<ext>`).
        public let source: String

        /// MIME type when known.
        public let type: String?

        // MARK: Internal

        enum CodingKeys: String, CodingKey {
            case name
            case source
            case type
        }

        /// Where the exported file currently lives on disk; used by
        /// ``AllureFormatter/write(report:to:startedAt:makeUUID:)`` to copy the
        /// file next to the result JSONs. Not part of the Allure schema.
        let originalPath: URL
    }

    /// A test step mapped from an XCTest activity.
    public struct Step: Encodable {
        public let name: String
        public let status: String
        public let stage: String
        public let start: Int
        public let stop: Int
        public let steps: [Self]
        public let attachments: [Attachment]
    }

    public let uuid: String
    public let historyID: String
    public let fullName: String
    public let name: String
    public let status: String
    public let stage: String
    public let start: Int
    public let stop: Int
    public let description: String?
    public let labels: [Label]
    public let parameters: [Parameter]
    public let statusDetails: StatusDetails?
    public let steps: [Step]
    public var attachments: [Attachment]

    // MARK: Internal

    /// The Allure 2 schema spells the key `historyId`; the property follows
    /// Swift acronym casing, so the mapping is explicit.
    enum CodingKeys: String, CodingKey {
        case uuid
        case historyID = "historyId"
        case fullName
        case name
        case status
        case stage
        case start
        case stop
        case description
        case labels
        case parameters
        case statusDetails
        case steps
        case attachments
    }

    /// All attachments of the result, including the ones nested in steps.
    /// ``AllureFormatter/write(report:to:startedAt:makeUUID:)`` copies files
    /// from here so nothing referenced stays behind.
    var allAttachments: [Attachment] {
        func collect(_ steps: [Step]) -> [Attachment] {
            steps.flatMap { $0.attachments + collect($0.steps) }
        }
        return attachments + collect(steps)
    }
}
