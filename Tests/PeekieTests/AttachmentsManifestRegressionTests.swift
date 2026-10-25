import Foundation
import Testing
@testable import PeekieSDK

struct AttachmentsManifestRegressionTests {
    @Test
    func retainedUnassociatedBucketDecodesWithoutInventingATest() throws {
        let manifest = try #require(Bundle.module.resourceURL)
            .appendingPathComponent("Resources/UnassociatedIssues/manifest.json")
        let dto = try JSONDecoder().decode(AttachmentsDTO.self, from: Data(contentsOf: manifest))
        #expect(dto.count == 2)
        #expect(dto[0].testIdentifierURL == nil)
        #expect(dto[0].attachments.count == 8)
        #expect(dto[1].testIdentifierURL == "test://com.apple.xcode/Example/ExampleTests/passes()")
    }
}
