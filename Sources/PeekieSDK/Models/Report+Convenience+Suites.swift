import Foundation

extension Report {
    // MARK: - Suite parsing

    /// Result of walking one `Unit test bundle` node: any `@Test`s declared at the
    /// bundle root (no enclosing `@Suite`), plus the top-level suites and their
    /// nested-suite trees.
    struct BundleTestNodes {
        var rootLevelTests: Set<Module.Suite.RepeatableTest>
        var suites: [Module.Suite]
    }

    /// Walks `testResultsDTO` and produces a `[testBundleName: BundleTestNodes]`
    /// mapping. The bundle name comes straight from the unit test bundle node —
    /// aliasing to a coverage-target name (e.g. `PeekieTests` → `Peekie`) happens
    /// at the call site.
    static func buildSuites(
        from testResultsDTO: TestResultsDTO,
        attachmentLookup: [AttachmentLookupKey: [Module.Suite.RepeatableTest.Test.Attachment]] = [:]
    )
        -> [String: BundleTestNodes]
    {
        var byBundle = [String: BundleTestNodes]()

        for rootNode in testResultsDTO.testNodes where rootNode.nodeType == .testPlan {
            guard let unitTestBundles = rootNode.children else {
                continue
            }

            for testNode in unitTestBundles where testNode.nodeType == .unitTestBundle {
                let bundleName = testNode.name
                let bundleChildren = (testNode.children ?? []).filter { $0.isMetadata == false }

                var rootLevelTests = Set<Module.Suite.RepeatableTest>()
                var suites = [Module.Suite]()

                for child in bundleChildren {
                    switch child.nodeType {
                    case .testCase:
                        // Root-level @Test function — no enclosing @Suite.
                        rootLevelTests.insert(
                            buildRepeatableTest(from: child, attachmentLookup: attachmentLookup)
                        )

                    case .testSuite:
                        suites.append(
                            buildSuite(
                                from: child,
                                parentPath: nil,
                                attachmentLookup: attachmentLookup
                            )
                        )

                    default:
                        continue
                    }
                }

                let existing = byBundle[bundleName] ?? BundleTestNodes(
                    rootLevelTests: [],
                    suites: []
                )
                byBundle[bundleName] = BundleTestNodes(
                    rootLevelTests: existing.rootLevelTests.union(rootLevelTests),
                    suites: existing.suites + suites
                )
            }
        }

        return byBundle
    }

    /// Recursively builds a `Suite` from a `Test Suite` node. Walks both nested
    /// `Test Suite` children (becoming `nestedSuites`) and `Test Case` children
    /// (becoming `repeatableTests`). `parentPath` is the `" / "`-joined chain of
    /// ancestor suite names from the bundle root; pass `nil` for top-level suites.
    private static func buildSuite(
        from testSuite: TestResultsDTO.TestNode,
        parentPath: String?,
        attachmentLookup: [AttachmentLookupKey: [Module.Suite.RepeatableTest.Test.Attachment]] = [:]
    )
        -> Module.Suite
    {
        let fullPath = parentPath.map { "\($0) / \(testSuite.name)" } ?? testSuite.name

        // Edge case: nested `Test Suite` nodes can legitimately carry a `null`
        // `nodeIdentifierURL` in some xcresult outputs. We synthesize one from the
        // parent's URL when available; otherwise fall back to a synthetic
        // `test://` URL keyed on `fullPath` so the suite is still addressable
        // downstream (e.g. for SonarFormatter caching) without dropping it.
        let nodeIdentifierURL = testSuite.nodeIdentifierURL
            ?? "test://com.apple.xcode/_synthesized/\(fullPath)"

        var repeatableTests = Set<Module.Suite.RepeatableTest>()
        var nestedSuites = [Module.Suite]()

        let filteredChildren = (testSuite.children ?? []).filter { $0.isMetadata == false }
        for child in filteredChildren {
            switch child.nodeType {
            case .testCase:
                repeatableTests.insert(
                    buildRepeatableTest(from: child, attachmentLookup: attachmentLookup)
                )

            case .testSuite:
                nestedSuites.append(
                    buildSuite(
                        from: child,
                        parentPath: fullPath,
                        attachmentLookup: attachmentLookup
                    )
                )

            default:
                continue
            }
        }

        return Module.Suite(
            name: testSuite.name,
            nodeIdentifierURL: nodeIdentifierURL,
            fullPath: fullPath,
            repeatableTests: repeatableTests,
            nestedSuites: nestedSuites
        )
    }

    /// Converts a `Test Case` node into a `RepeatableTest`. Used both by top-level
    /// bundle walking (root-level `@Test` cases) and by suite walking (cases inside
    /// `@Suite` types and `XCTestCase` subclasses).
    private static func buildRepeatableTest(
        from testCase: TestResultsDTO.TestNode,
        attachmentLookup: [AttachmentLookupKey: [Module.Suite.RepeatableTest.Test.Attachment]] = [:]
    )
        -> Module.Suite.RepeatableTest
    {
        var repeatable = Module.Suite.RepeatableTest(name: testCase.name, tests: [])

        let filteredChildren = (testCase.children ?? []).filter { $0.isMetadata == false }
        for child in filteredChildren {
            processTestNode(
                child,
                path: [],
                testCase: testCase,
                attachmentLookup: attachmentLookup,
                into: &repeatable
            )
        }

        if repeatable.tests.isEmpty {
            var test = Module.Suite.RepeatableTest.Test(from: testCase)
            test.attachments = lookupAttachments(
                for: testCase,
                repetition: nil,
                lookup: attachmentLookup
            )
            repeatable.tests.append(test)
        }
        return repeatable
    }

    private static func processTestNode(
        _ node: TestResultsDTO.TestNode,
        path: [Module.Suite.RepeatableTest.PathNode],
        testCase: TestResultsDTO.TestNode,
        attachmentLookup: [AttachmentLookupKey: [Module.Suite.RepeatableTest.Test.Attachment]],
        into repeatable: inout Module.Suite.RepeatableTest
    ) {
        var newPath = path
        if let pathNode = makePathNode(from: node) {
            newPath.append(pathNode)
        }

        if node.nodeType == .repetition {
            appendRepetitionTest(
                node: node,
                path: newPath,
                testCase: testCase,
                attachmentLookup: attachmentLookup,
                into: &repeatable
            )
            return
        }

        let filteredChildren = (node.children ?? []).filter { $0.isMetadata == false }

        if node.nodeType == .arguments {
            let hasRepetitions = filteredChildren.contains { $0.nodeType == .repetition }
            if hasRepetitions == false {
                appendArgumentsTest(
                    node: node,
                    path: newPath,
                    testCase: testCase,
                    attachmentLookup: attachmentLookup,
                    into: &repeatable
                )
                return
            }
        }

        for child in filteredChildren {
            processTestNode(
                child,
                path: newPath,
                testCase: testCase,
                attachmentLookup: attachmentLookup,
                into: &repeatable
            )
        }
    }

    private static func appendRepetitionTest(
        node: TestResultsDTO.TestNode,
        path: [Module.Suite.RepeatableTest.PathNode],
        testCase: TestResultsDTO.TestNode,
        attachmentLookup: [AttachmentLookupKey: [Module.Suite.RepeatableTest.Test.Attachment]],
        into repeatable: inout Module.Suite.RepeatableTest
    ) {
        do {
            var test = try Module.Suite.RepeatableTest.Test(
                from: node,
                path: path,
                testCaseName: testCase.name,
                testCase: testCase
            )
            test.attachments = lookupAttachments(
                for: testCase,
                repetition: repetitionNumber(from: node.name),
                lookup: attachmentLookup
            )
            repeatable.tests.append(test)
        } catch {
            // Skip malformed repetition node; we surface what we can.
        }
    }

    private static func appendArgumentsTest(
        node: TestResultsDTO.TestNode,
        path: [Module.Suite.RepeatableTest.PathNode],
        testCase: TestResultsDTO.TestNode,
        attachmentLookup: [AttachmentLookupKey: [Module.Suite.RepeatableTest.Test.Attachment]],
        into repeatable: inout Module.Suite.RepeatableTest
    ) {
        var test = Module.Suite.RepeatableTest.Test(
            from: node,
            path: path,
            testCase: testCase
        )
        test.attachments = lookupAttachments(
            for: testCase,
            repetition: nil,
            lookup: attachmentLookup
        )
        repeatable.tests.append(test)
    }

    /// Joins a parsed `testCase` node + optional repetition number against the
    /// flat manifest lookup. When the test ran without retries, falls back to
    /// any entries the manifest emitted with `repetitionNumber == nil`.
    private static func lookupAttachments(
        for testCase: TestResultsDTO.TestNode,
        repetition: Int?,
        lookup: [AttachmentLookupKey: [Module.Suite.RepeatableTest.Test.Attachment]]
    )
        -> [Module.Suite.RepeatableTest.Test.Attachment]
    {
        guard let testIdentifierURL = testCase.nodeIdentifierURL,
              lookup.isEmpty == false
        else {
            return []
        }

        let key = AttachmentLookupKey(
            testIdentifierURL: testIdentifierURL,
            repetitionNumber: repetition
        )
        if let exact = lookup[key] {
            return exact
        }
        // Fallback: a test that the parser sees as a single run may still have
        // manifest entries tagged with `repetitionNumber: 1`. Surface those so
        // we don't drop attachments for one-shot tests.
        if repetition == nil {
            let oneShotKey = AttachmentLookupKey(
                testIdentifierURL: testIdentifierURL,
                repetitionNumber: 1
            )
            if let fallback = lookup[oneShotKey] {
                return fallback
            }
        }
        return []
    }

    /// Parses a repetition number out of a `Repetition` node name (e.g.
    /// `"Repetition 2"` → `2`). Returns `nil` when no trailing integer is found.
    private static func repetitionNumber(from name: String) -> Int? {
        let scanner = Scanner(string: name)
        scanner.charactersToBeSkipped = .whitespaces
        _ = scanner.scanCharacters(from: .letters)
        return scanner.scanInt()
    }

    // MARK: - Module projection

    /// Maps test-bundle names to their canonical coverage-target names so suites land on
    /// the same Module as coverage. Mirrors the matching rules used in `4.x`:
    /// equality, equality after stripping a `Tests` suffix, or one name containing the
    /// other's base name.
    private static func makePathNode(
        from node: TestResultsDTO.TestNode
    )
        -> Module.Suite.RepeatableTest.PathNode?
    {
        switch node.nodeType {
        case .device, .arguments, .repetition:
            let duration: Measurement<UnitDuration>? = node.durationInSeconds.map {
                .init(value: $0 * 1000, unit: Module.Suite.RepeatableTest.Test.defaultDurationUnit)
            }
            return .init(
                name: node.name,
                type: .init(from: node.nodeType),
                result: pathNodeStatus(from: node.result),
                duration: duration,
                message: node.failureMessage ?? node.skipMessage
            )

        default:
            return nil
        }
    }

    private static func pathNodeStatus(
        from dtoResult: TestResultsDTO.TestNode.Result?
    )
        -> Module.Suite.RepeatableTest.Test.Status?
    {
        guard let dtoResult else {
            return nil
        }

        switch dtoResult {
        case .passed:
            return .success
        case .failed:
            return .failure
        case .skipped:
            return .skipped
        case .expectedFailure:
            return .expectedFailure
        }
    }

    static func aliasTestBundlesToCoverageTargets(
        testBundleNames: Set<String>,
        coverageTargetNames: Set<String>
    )
        -> [String: String]
    {
        // Iterate both sides in sorted order so the chosen alias is deterministic
        // when more than one coverage target satisfies the matching predicate.
        let sortedTargets = coverageTargetNames.sorted()
        var aliases = [String: String]()
        for bundle in testBundleNames.sorted() {
            if coverageTargetNames.contains(bundle) {
                continue
            }
            let bundleBase = bundle.replacing("Tests", with: "")
            var match: String?
            for target in sortedTargets {
                let targetBase = target.replacing("Tests", with: "")
                if target == bundle || targetBase == bundleBase
                    || bundle.contains(target) || target.contains(bundleBase)
                {
                    match = target
                    break
                }
            }
            if let match {
                aliases[bundle] = match
            }
        }
        return aliases
    }

    static func buildModules(
        files: [File],
        testNodesByModule: [String: BundleTestNodes],
        coverageReportDTO: CoverageReportDTO?
    )
        -> [Module]
    {
        var moduleNames = Set<String>()
        if let coverageReportDTO {
            moduleNames.formUnion(coverageReportDTO.targets.map(\.name))
        }
        moduleNames.formUnion(testNodesByModule.keys)

        return moduleNames.sorted().map { name in
            buildModule(
                name: name,
                files: files,
                testNodes: testNodesByModule[name],
                coverageReportDTO: coverageReportDTO
            )
        }
    }

    private static func buildModule(
        name: String,
        files: [File],
        testNodes: BundleTestNodes?,
        coverageReportDTO: CoverageReportDTO?
    )
        -> Module
    {
        let moduleFiles = files.filter { $0.module == name }
        let moduleCoverage = moduleCoverage(for: name, coverageReportDTO: coverageReportDTO)
        return Module(
            name: name,
            files: moduleFiles,
            coverage: moduleCoverage,
            rootLevelTests: testNodes?.rootLevelTests ?? [],
            suites: testNodes?.suites ?? []
        )
    }

    private static func moduleCoverage(
        for name: String,
        coverageReportDTO: CoverageReportDTO?
    )
        -> Coverage?
    {
        guard let target = coverageReportDTO?.targets.first(where: { $0.name == name }),
              target.executableLines > 0
        else {
            return nil
        }

        return Coverage(
            coveredLines: target.coveredLines,
            totalLines: target.executableLines,
            coverage: target.lineCoverage
        )
    }

    // MARK: - Total coverage

    static func computeTotalCoverage(
        includeCoverage: Bool,
        coverageReportDTO: CoverageReportDTO?,
        files: [File]
    )
        -> Double?
    {
        guard includeCoverage else {
            return nil
        }

        if let lineCoverage = coverageReportDTO?.lineCoverage, lineCoverage > 0 {
            return lineCoverage
        }
        let fileCoverages = files.compactMap(\.coverage)
        guard fileCoverages.isEmpty == false else {
            return nil
        }

        let total = fileCoverages.reduce(0) { $0 + $1.totalLines }
        let covered = fileCoverages.reduce(0) { $0 + $1.coveredLines }
        return total != 0 ? Double(covered) / Double(total) : 0.0
    }
}
