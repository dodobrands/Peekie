import Foundation

// MARK: - AttachmentsDTO

/// Top-level shape of `manifest.json` produced by
/// `xcrun xcresulttool export attachments`. The CLI writes the binary
/// attachments to `outputDirectory` and emits one manifest entry per
/// test that captured at least one attachment.
typealias AttachmentsDTO = [AttachmentDetails]

// MARK: - AttachmentDetails

struct AttachmentDetails: Decodable {
    let testIdentifierURL: String
    let attachments: [Entry]
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
