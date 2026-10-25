import ArgumentParser
import Foundation
import PeekieSDK

extension Report {
    func checkUnassociatedIssues(in directory: URL? = nil) throws {
        guard unassociatedAttachments.isEmpty == false else {
            return
        }

        let paths = unassociatedAttachments.map { attachment in
            (directory?.appendingPathComponent(attachment.exportedFileName) ?? attachment.path).path
        }
        let message = "Issues recorded without an associated test or suite: "
            + "\(unassociatedAttachments.count) diagnostic attachments (not a test count).\n"
            + paths.joined(separator: "\n")
        if unassociatedAttachments.contains(where: \.isAssociatedWithFailure) {
            throw ValidationError(message)
        }
        FileHandle.standardError.write(Data(("Warning: " + message + "\n").utf8))
    }
}
