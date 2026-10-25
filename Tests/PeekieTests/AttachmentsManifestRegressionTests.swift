import Foundation
import Testing
@testable import PeekieSDK

struct AttachmentsManifestRegressionTests {
    @Test
    func retainedUnassociatedBucketReproducesMissingURL() throws {
        let manifest = try #require(Bundle.module.resourceURL)
            .appendingPathComponent("Resources/UnassociatedIssues/manifest.json")
        let data = try Data(contentsOf: manifest)
        do {
            _ = try JSONDecoder().decode(AttachmentsDTO.self, from: data)
            Issue.record("Expected the existing decoder to reject the unassociated bucket")
        } catch DecodingError.keyNotFound(let key, let context) {
            #expect(key.stringValue == "testIdentifierURL")
            #expect(context.codingPath.first?.intValue == 0)
        }
    }
}
