import Foundation

// MARK: - AttachmentsDTO

/// Top-level shape of `manifest.json` produced by
/// `xcrun xcresulttool export attachments`. The CLI writes the binary
/// attachments to `outputDirectory` and emits one manifest entry per
/// test or unassociated issue bucket that captured attachments.
typealias AttachmentsDTO = [AttachmentDetails]

// MARK: - AttachmentDetails

struct AttachmentDetails: Decodable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        testIdentifierURL = try container.decodeIfPresent(String.self, forKey: .testIdentifierURL)
        if testIdentifierURL?.isEmpty == true {
            throw DecodingError.dataCorruptedError(
                forKey: .testIdentifierURL, in: container,
                debugDescription: "Empty testIdentifierURL on an attachment record"
            )
        }
        if testIdentifierURL == nil {
            let identifier = try container.decodeIfPresent(String.self, forKey: .testIdentifier)
            guard identifier == Self.unassociatedIssuesIdentifier else {
                throw DecodingError.keyNotFound(
                    CodingKeys.testIdentifierURL,
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Missing testIdentifierURL on an unknown attachment record"
                    )
                )
            }
        }
        attachments = try container.decode([Entry].self, forKey: .attachments)
    }

    // MARK: Internal

    static let unassociatedIssuesIdentifier = "Issues recorded without an associated test or suite"

    let testIdentifierURL: String?
    let attachments: [Entry]

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case testIdentifierURL
        case testIdentifier
        case attachments
    }
}

// MARK: AttachmentDetails.Entry

extension AttachmentDetails {
    /// One attachment entry inside `manifest.json`. Every field except
    /// `exportedFileName` and `suggestedHumanReadableName` is optional because
    /// `xcresulttool` is not contractually obligated to emit all of them across
    /// Xcode versions and test sources.
    struct Entry: Decodable {
        let configurationName: String?
        let deviceID: String?
        let exportedFileName: String
        let isAssociatedWithFailure: Bool
        let repetitionNumber: Int?
        let suggestedHumanReadableName: String
        let timestamp: Double?
    }
}
