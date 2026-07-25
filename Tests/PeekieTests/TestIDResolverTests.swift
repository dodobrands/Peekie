import Foundation
import Testing
@testable import PeekieSDK

/// `peekie tests` prints qualified names built from display names (with an
/// ` [arguments]` suffix for parameterized cases), but `xcresulttool export
/// attachments --test-id` accepts only node identifiers, so `resolveTestID`
/// must translate every spelling peekie itself produces and pass everything
/// else through untouched.
struct TestIDResolverTests {
    // MARK: Internal

    @Test
    func mergedArgumentsNameResolvesToIdentifier() {
        let dto = makeFixture()

        let mergedName = "Photo galery snapshots [<UITraitCollection: 0x102b7ae40; >]"

        let resolved = dto.resolveTestID(
            "PhotoGaleryViewControllerSnapshotTests/\(mergedName)"
        )

        #expect(resolved == Self.parameterizedIdentifier)
    }

    @Test
    func displayPathWithoutArgumentsResolvesToIdentifier() {
        let dto = makeFixture()

        let resolved = dto.resolveTestID(
            "PhotoGaleryViewControllerSnapshotTests/Photo galery snapshots"
        )

        #expect(resolved == Self.parameterizedIdentifier)
    }

    @Test
    func bundlePrefixedPathResolvesToIdentifier() {
        let dto = makeFixture()

        let resolved = dto.resolveTestID(
            "RateTests/PhotoGaleryViewControllerSnapshotTests/Photo galery snapshots"
        )

        #expect(resolved == Self.parameterizedIdentifier)
    }

    @Test
    func qualifiedNameWithSpacedSeparatorsResolvesToIdentifier() {
        let dto = makeFixture()

        let mergedName = "Photo galery snapshots [<UITraitCollection: 0x102b7ae40; >]"

        let resolved = dto.resolveTestID(
            "RateTests / PhotoGaleryViewControllerSnapshotTests / \(mergedName)"
        )

        #expect(resolved == Self.parameterizedIdentifier)
    }

    @Test
    func exactIdentifierPassesThroughUnchanged() {
        let dto = makeFixture()

        let resolved = dto.resolveTestID(Self.parameterizedIdentifier)

        #expect(resolved == Self.parameterizedIdentifier)
    }

    @Test
    func unknownReferencePassesThroughUnchanged() {
        let dto = makeFixture()

        let resolved = dto.resolveTestID("SomeSuite/not a known test")

        #expect(resolved == "SomeSuite/not a known test")
    }

    @Test
    func xctestStylePathResolvesToItself() {
        let dto = makeFixture()

        let resolved = dto.resolveTestID("CheckOutTests/test_NIP()")

        #expect(resolved == "CheckOutTests/test_NIP()")
    }

    @Test
    func nestedSuitePathResolvesToIdentifier() {
        let dto = makeFixture()

        let resolved = dto.resolveTestID("OuterSuite/InnerSuite/nested case")

        #expect(resolved == "OuterSuite/InnerSuite/`nested case`()")
    }

    @Test
    func bracketedDisplayNameWinsOverSuffixStripping() {
        // A display name that genuinely ends with a bracket must match
        // verbatim; the ` [arguments]` stripping applies only after a miss.
        let dto = makeFixture()

        let resolved = dto.resolveTestID("EdgeSuite/edge [special]")

        #expect(resolved == "EdgeSuite/`edge [special]`()")
    }

    @Test
    func caseWithoutIdentifierPassesThroughUnchanged() {
        let dto = makeFixture()

        let resolved = dto.resolveTestID("EdgeSuite/no identifier here")

        #expect(resolved == "EdgeSuite/no identifier here")
    }

    // MARK: Private

    private static let parameterizedIdentifier =
        "PhotoGaleryViewControllerSnapshotTests/`Photo galery snapshots`(traits:)"

    /// Mirrors the tree of a real merged unit-chunk bundle: a Swift Testing
    /// parameterized case (display name + argument children), an XCTest-style
    /// case whose identifier equals its display path, a nested suite, and
    /// edge cases for bracketed names and missing identifiers.
    private func makeFixture() -> TestResultsDTO {
        TestResultsDTO(testNodes: [
            makeNode(
                name: "Test Scheme Action",
                nodeType: .testPlan,
                children: [
                    makeNode(
                        name: "RateTests",
                        nodeType: .unitTestBundle,
                        children: [
                            makeNode(
                                name: "PhotoGaleryViewControllerSnapshotTests",
                                nodeType: .testSuite,
                                children: [
                                    makeNode(
                                        name: "Photo galery snapshots",
                                        nodeType: .testCase,
                                        children: [
                                            makeNode(
                                                name: "<UITraitCollection: 0x102b7ae40; >",
                                                nodeType: .arguments
                                            ),
                                            makeNode(
                                                name: "<UITraitCollection: 0x102b7af80; "
                                                    + "UserInterfaceStyle = Dark>",
                                                nodeType: .arguments
                                            ),
                                        ],
                                        nodeIdentifier: Self.parameterizedIdentifier
                                    ),
                                ]
                            ),
                        ]
                    ),
                    makeNode(
                        name: "E2ETests",
                        nodeType: .uiTestBundle,
                        children: [
                            makeNode(
                                name: "CheckOutTests",
                                nodeType: .testSuite,
                                children: [
                                    makeNode(
                                        name: "test_NIP()",
                                        nodeType: .testCase,
                                        nodeIdentifier: "CheckOutTests/test_NIP()"
                                    ),
                                ]
                            ),
                            makeNode(
                                name: "OuterSuite",
                                nodeType: .testSuite,
                                children: [
                                    makeNode(
                                        name: "InnerSuite",
                                        nodeType: .testSuite,
                                        children: [
                                            makeNode(
                                                name: "nested case",
                                                nodeType: .testCase,
                                                nodeIdentifier: "OuterSuite/InnerSuite/`nested case`()"
                                            ),
                                        ]
                                    ),
                                ]
                            ),
                            makeNode(
                                name: "EdgeSuite",
                                nodeType: .testSuite,
                                children: [
                                    makeNode(
                                        name: "edge [special]",
                                        nodeType: .testCase,
                                        nodeIdentifier: "EdgeSuite/`edge [special]`()"
                                    ),
                                    makeNode(
                                        name: "no identifier here",
                                        nodeType: .testCase
                                    ),
                                ]
                            ),
                        ]
                    ),
                ]
            ),
        ])
    }

    private func makeNode(
        name: String,
        nodeType: TestResultsDTO.TestNode.NodeType,
        children: [TestResultsDTO.TestNode]? = nil,
        nodeIdentifier: String? = nil
    )
        -> TestResultsDTO.TestNode
    {
        TestResultsDTO.TestNode(
            children: children,
            durationInSeconds: nil,
            name: name,
            nodeIdentifierURL: nil,
            nodeType: nodeType,
            result: nil,
            nodeIdentifier: nodeIdentifier
        )
    }
}
