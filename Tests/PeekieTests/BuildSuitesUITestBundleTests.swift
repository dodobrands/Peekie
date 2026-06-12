import Foundation
import Testing
@testable import PeekieSDK

struct BuildSuitesUITestBundleTests {
    @Test
    func decodesUITestBundleRawValue() throws {
        // `"UI test bundle"` is the raw value xcresulttool emits for UI test bundles
        // (alongside `"Unit test bundle"` for unit-test ones). Both must decode to
        // dedicated cases so the bundleMapping filter can include them.
        let data = Data("\"UI test bundle\"".utf8)
        let decoded = try JSONDecoder().decode(TestResultsDTO.TestNode.NodeType.self, from: data)
        #expect(decoded == .uiTestBundle)
    }

    @Test
    func buildSuitesIncludesUITestBundle() {
        // Regression guard for issue #207 — `buildSuites` used to filter
        // `where nodeType == .unitTestBundle`, silently dropping UI test bundles
        // and leaving the modules array empty.
        let testCase = TestResultsDTO.TestNode(
            children: nil,
            durationInSeconds: 0.5,
            name: "test_open_cart()",
            nodeIdentifierURL: nil,
            nodeType: .testCase,
            result: .failed
        )

        let suite = TestResultsDTO.TestNode(
            children: [testCase],
            durationInSeconds: nil,
            name: "CartTests",
            nodeIdentifierURL: nil,
            nodeType: .testSuite,
            result: nil
        )

        let uiBundle = TestResultsDTO.TestNode(
            children: [suite],
            durationInSeconds: nil,
            name: "E2ETests",
            nodeIdentifierURL: nil,
            nodeType: .uiTestBundle,
            result: nil
        )

        let plan = TestResultsDTO.TestNode(
            children: [uiBundle],
            durationInSeconds: nil,
            name: "E2ESmoke",
            nodeIdentifierURL: nil,
            nodeType: .testPlan,
            result: nil
        )

        let dto = TestResultsDTO(testNodes: [plan])

        let mapping = Report.buildSuites(from: dto)

        #expect(mapping["E2ETests"] != nil)
        #expect(mapping["E2ETests"]?.suites.count == 1)
        #expect(mapping["E2ETests"]?.suites.first?.name == "CartTests")
    }
}
