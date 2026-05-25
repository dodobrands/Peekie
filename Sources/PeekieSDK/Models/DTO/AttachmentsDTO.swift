//
//  AttachmentsDTO.swift
//  Peekie
//
//  Created by Jonathan Bailey on 10/04/2026.
//

typealias AttachmentsDTO = [AttachmentDetails]

struct AttachmentDetails: Decodable, Sendable {
    let testIdentifierURL: String
    let attachments: [Attachment]

    struct Attachment: Decodable, Sendable {
        let exportedFileName: String
        let suggestedHumanReadableName: String
        let repetitionNumber: Int?
        let arguments: [String]?
    }
}
