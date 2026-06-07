import Foundation
import PeekieTestHelpers
import Testing
@testable import PeekieSDK

/// Explicit presence checks for every typed `IssueType` case that `swift-tests-example`
/// is set up to emit (see `SPM/Sources/Calculator/WarningsCatalog.swift`). Snapshot
/// tests alone wouldn't catch a regression where the enum mapping drops a typed case —
/// the diff would look like a count change and could be accepted by mistake. These
/// asserts make a missing typed case impossible to merge.
struct IssueTypeRegressionTests {
    @Test(
        arguments: ["SPM-26.5-iOS.xcresult", "Xcworkspace-26.5-iOS.xcresult"]
    )
    func fixtureSurfacesEveryTypedIssueType(_ fileName: String) async throws {
        // Both bundles ship a `WarningsCatalog.swift` (SPM in the Calculator
        // target, Xcworkspace in the XcodeprojExampleFramework target) so each
        // surfaces representatives of every typed `IssueType` case shipped in 5.0.
        let originalPath = try Constants.url(for: fileName)
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer { try? FileManager.default.removeItem(at: reportPath) }

        let report = try await Report(
            xcresultPath: reportPath,
            includeCoverage: false,
            includeWarnings: true,
            includeTests: false
        )
        let warnings = report.warnings

        #expect(
            warnings.contains { $0.type == .swiftCompilerWarning },
            "expected at least one .swiftCompilerWarning"
        )
        #expect(
            warnings.contains { $0.type == .swiftCompilerError },
            "expected at least one .swiftCompilerError (from #warning(\"…\") caret)"
        )
        #expect(
            warnings.contains { $0.type == .deprecatedDeclaration },
            "expected at least one .deprecatedDeclaration (from @available(*, deprecated))"
        )
        #expect(
            warnings.contains { $0.type == .noUsage },
            "expected at least one .noUsage (from unused result of call)"
        )

        // No issue should silently fall through to `.unknown(_)` — if Apple ships a
        // new typed group, we want to know and add it to the enum.
        let unknowns: [String] = warnings.compactMap {
            if case .unknown(let raw) = $0.type {
                raw
            } else {
                nil
            }
        }
        let unknownsList = Set(unknowns).sorted().joined(separator: ", ")
        #expect(unknowns.isEmpty, "unexpected unknown issueType(s): \(unknownsList)")
    }

    @Test
    func deprecatedDeclarationsAppearOncePerCallSiteNotOnce() async throws {
        // Regression for #161: dedup was dropped, so 3 identical call sites must produce
        // 3 records (one per line), not collapse to a single entry.
        let originalPath = try Constants.url(for: "SPM-26.5-iOS.xcresult")
        let reportPath = try Constants.copyXcresultToTemporaryDirectory(originalPath)
        defer { try? FileManager.default.removeItem(at: reportPath) }

        let report = try await Report(
            xcresultPath: reportPath,
            includeCoverage: false,
            includeWarnings: true,
            includeTests: false
        )

        let deprecated = report.warnings.filter { $0.type == .deprecatedDeclaration }
        #expect(
            deprecated.count >= 3,
            "expected ≥ 3 deprecated records (one per call site); got \(deprecated.count)"
        )

        let distinctLines = Set(deprecated.compactMap { $0.location?.startLine })
        #expect(
            distinctLines.count >= 3,
            "expected deprecated records to come from ≥ 3 distinct lines (#161 dedup dropped)"
        )
    }
}
