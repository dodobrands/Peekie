import Foundation

extension AllureFormatter {
    func writeUnassociatedAttachments(
        _ attachments: [Report.Module.Suite.RepeatableTest.Test.Attachment],
        to outputDirectory: URL
    ) throws
        -> Int
    {
        guard attachments.isEmpty == false else {
            return 0
        }

        let directory = outputDirectory.appendingPathComponent("unassociated-issues")
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var exported = [AllureTestResult.Attachment]()
        var properties = [String]()
        let severity = attachments.contains(where: \.isAssociatedWithFailure) ? "ERROR" : "WARNING"
        properties.append(
            "Peekie.unassociatedIssues=\(severity): \(attachments.count) diagnostic attachments; "
                + "no associated test or suite. See unassociated-issues/manifest.json"
        )
        for (index, attachment) in attachments.enumerated() {
            let destination = directory.appendingPathComponent(attachment.exportedFileName)
            try fileManager.copyItem(at: attachment.path, to: destination)
            exported.append(.init(
                name: attachment.name,
                source: attachment.exportedFileName,
                type: attachment.contentType,
                originalPath: destination
            ))
            let text = attachment.contentType == "text/plain"
                ? try String(contentsOf: destination, encoding: .utf8)
                : "\(attachment.name): unassociated-issues/\(attachment.exportedFileName)"
            properties
                .append("Peekie.unassociatedDiagnostic.\(index + 1)=\(Self.propertyValue(text))")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(exported).write(to: directory.appendingPathComponent("manifest.json"))

        // Allure displays launch-wide properties without adding tests or claiming test ownership.
        let environment = outputDirectory.appendingPathComponent("environment.properties")
        var data = fileManager
            .fileExists(atPath: environment.path) ? try Data(contentsOf: environment) : Data()
        data.append(Data(("\n" + properties.joined(separator: "\n") + "\n").utf8))
        try data.write(to: environment, options: .atomic)
        return attachments.count
    }

    private static func propertyValue(_ value: String) -> String {
        value.utf16
            .map { unit in
                switch unit {
                case 0x5C:
                    "\\\\"
                case 0x20:
                    "\\ "
                case 0x21...0x7E:
                    String(decoding: [unit], as: UTF16.self)
                default:
                    String(format: "\\u%04x", unit)
                }
            }
            .joined()
    }
}
