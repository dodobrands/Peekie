import Foundation

extension Report {
    // MARK: - Suite parsing

    /// Walks `testResultsDTO` and produces a `[testBundleName: [Suite]]` mapping. The
    /// bundle name comes straight from the unit test bundle node — aliasing to a
    /// coverage-target name (e.g. `PeekieTests` → `Peekie`) happens at the call site.
    static func buildSuites(
        from testResultsDTO: TestResultsDTO
    )
        -> [String: [Module.Suite]]
    {
        var byBundle = [String: [Module.Suite]]()

        for rootNode in testResultsDTO.testNodes where rootNode.nodeType == .testPlan {
            guard let unitTestBundles = rootNode.children else {
                continue
            }

            for testNode in unitTestBundles where testNode.nodeType == .unitTestBundle {
                let bundleName = testNode.name
                var suites = [Module.Suite]()
                for testSuite in testNode.children ?? [] where testSuite.nodeType == .testSuite {
                    guard let nodeIdentifierURL = testSuite.nodeIdentifierURL else {
                        continue
                    }

                    let suite = buildSuite(
                        from: testSuite,
                        nodeIdentifierURL: nodeIdentifierURL
                    )
                    suites.append(suite)
                }
                byBundle[bundleName, default: []].append(contentsOf: suites)
            }
        }

        return byBundle
    }

    private static func buildSuite(
        from testSuite: TestResultsDTO.TestNode,
        nodeIdentifierURL: String
    )
        -> Module.Suite
    {
        var repeatableTests = Set<Module.Suite.RepeatableTest>()
        let filteredCases = (testSuite.children ?? []).filter { $0.isMetadata == false }
        for testCase in filteredCases where testCase.nodeType == .testCase {
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
            repeatableTests.insert(repeatable)
        }

        return Module.Suite(
            name: testSuite.name,
            nodeIdentifierURL: nodeIdentifierURL,
            repeatableTests: repeatableTests
        )
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
        suitesByModule: [String: [Module.Suite]],
        coverageReportDTO: CoverageReportDTO?
    )
        -> [Module]
    {
        var moduleNames = Set<String>()
        if let coverageReportDTO {
            moduleNames.formUnion(coverageReportDTO.targets.map(\.name))
        }
        moduleNames.formUnion(suitesByModule.keys)

        return moduleNames.sorted().map { name in
            let moduleFiles = files.filter { $0.module == name }

            let moduleCoverage: Coverage? =
                if let target = coverageReportDTO?.targets
                    .first(where: { $0.name == name }),
                    target.executableLines > 0
                {
                    Coverage(
                        coveredLines: target.coveredLines,
                        totalLines: target.executableLines,
                        coverage: target.lineCoverage
                    )
                } else {
                    nil
                }

            return Module(
                name: name,
                files: moduleFiles,
                coverage: moduleCoverage,
                suites: suitesByModule[name] ?? []
            )
        }
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
