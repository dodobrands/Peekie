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
        from testResultsDTO: TestResultsDTO
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
                        rootLevelTests.insert(buildRepeatableTest(from: child))

                    case .testSuite:
                        suites.append(buildSuite(from: child, parentPath: nil))

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
        parentPath: String?
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
                repeatableTests.insert(buildRepeatableTest(from: child))

            case .testSuite:
                nestedSuites.append(buildSuite(from: child, parentPath: fullPath))

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
        from testCase: TestResultsDTO.TestNode
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
                into: &repeatable
            )
        }

        if repeatable.tests.isEmpty {
            repeatable.tests.append(.init(from: testCase))
        }
        return repeatable
    }

    private static func processTestNode(
        _ node: TestResultsDTO.TestNode,
        path: [Module.Suite.RepeatableTest.PathNode],
        testCase: TestResultsDTO.TestNode,
        into repeatable: inout Module.Suite.RepeatableTest
    ) {
        var newPath = path
        if let pathNode = makePathNode(from: node) {
            newPath.append(pathNode)
        }

        if node.nodeType == .repetition {
            do {
                let test = try Module.Suite.RepeatableTest.Test(
                    from: node,
                    path: newPath,
                    testCaseName: testCase.name,
                    testCase: testCase
                )
                repeatable.tests.append(test)
            } catch {
                // Skip malformed repetition node; we surface what we can.
            }
            return
        }

        guard let nodeChildren = node.children else {
            if node.nodeType == .arguments {
                let test = Module.Suite.RepeatableTest.Test(
                    from: node,
                    path: newPath,
                    testCase: testCase
                )
                repeatable.tests.append(test)
            }
            return
        }

        let filteredChildren = nodeChildren.filter { $0.isMetadata == false }

        if node.nodeType == .arguments {
            let hasRepetitions = filteredChildren.contains { $0.nodeType == .repetition }
            if hasRepetitions == false {
                let test = Module.Suite.RepeatableTest.Test(
                    from: node,
                    path: newPath,
                    testCase: testCase
                )
                repeatable.tests.append(test)
                return
            }
        }

        for child in filteredChildren {
            processTestNode(child, path: newPath, testCase: testCase, into: &repeatable)
        }
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
