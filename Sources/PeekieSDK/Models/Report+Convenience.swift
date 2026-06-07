import Foundation
import Logging

extension Report {
    private static let logger = Logger(label: "com.peekie.report")

    /// Initializes a new instance of the `Report` using the provided `xcresultPath`.
    ///
    /// `files` is built as the primary index — every file the bundle has any signal about
    /// (coverage, warnings, errors) appears exactly once. `modules` is a projection: one
    /// entry per known target name, files filtered by `File.module`, test suites
    /// attached by target. Files belonging to test-less targets or to project-level
    /// build issues with no module signal still appear in `files` (with `module == nil`),
    /// so their warnings/errors are not silently lost.
    ///
    /// - Parameters:
    ///   - xcresultPath: The file URL of the `.xcresult` file to parse.
    ///   - includeCoverage: Whether to parse and include code coverage data. Defaults to `true`.
    ///   - includeWarnings: Whether to parse and include build warnings/errors. Defaults to `true`.
    /// - Throws: An error if the `.xcresult` file cannot be parsed.
    public init(
        xcresultPath: URL,
        includeCoverage: Bool = true,
        includeWarnings: Bool = true
    ) async throws {
        Self.logger.debug(
            "Initializing Report from xcresult",
            metadata: [
                "xcresultPath": "\(xcresultPath.path)",
                "includeCoverage": "\(includeCoverage)",
                "includeWarnings": "\(includeWarnings)",
            ]
        )

        let testResultsDTO = try await TestResultsDTO(from: xcresultPath)
        let buildResultsDTO: BuildResultsDTO? =
            includeWarnings ? try await BuildResultsDTO(from: xcresultPath) : nil
        let coverageReportDTO: CoverageReportDTO? =
            includeCoverage ? try await CoverageReportDTO(from: xcresultPath) : nil

        // Parse build issues
        let warningsByFileName: [String: [File.Issue]]
        let errorsByFileName: [String: [File.Issue]]
        if let buildResultsDTO {
            warningsByFileName = await Self.parseWarnings(from: buildResultsDTO)
            errorsByFileName = await Self.parseErrors(from: buildResultsDTO)
        } else {
            warningsByFileName = [:]
            errorsByFileName = [:]
        }

        let files = Self.buildFiles(
            coverageReportDTO: coverageReportDTO,
            warningsByFileName: warningsByFileName,
            errorsByFileName: errorsByFileName
        )

        // Build suites grouped by their test bundle name; alias test-bundle names to
        // canonical coverage-target names so they project onto the same Module.
        let suitesByBundle = Self.buildSuites(from: testResultsDTO)
        let coverageTargetNames = Set(coverageReportDTO?.targets.map(\.name) ?? [])
        let aliasing = Self.aliasTestBundlesToCoverageTargets(
            testBundleNames: Set(suitesByBundle.keys),
            coverageTargetNames: coverageTargetNames
        )
        var suitesByModule: [String: [Module.Suite]] = [:]
        for (bundle, suites) in suitesByBundle {
            let canonical = aliasing[bundle] ?? bundle
            suitesByModule[canonical, default: []].append(contentsOf: suites)
        }

        let modules = Self.buildModules(
            files: files,
            suitesByModule: suitesByModule,
            coverageReportDTO: coverageReportDTO
        )

        let totalCoverage: Double? = Self.computeTotalCoverage(
            includeCoverage: includeCoverage,
            coverageReportDTO: coverageReportDTO,
            files: files
        )

        self.files = files
        self.modules = modules
        self.coverage = totalCoverage

        Self.logger.debug(
            "Report initialization completed",
            metadata: [
                "files": "\(files.count)",
                "modules": "\(modules.count)",
                "totalCoverage": totalCoverage.map { "\($0)" } ?? "nil",
            ]
        )
    }

    // MARK: - File index

    /// Seeds the file index from coverage (paths give us identity and module attribution),
    /// then folds in warnings/errors keyed by basename. Issues whose basename matches an
    /// already-indexed file attach to it. Issues whose basename matches nothing produce a
    /// new `File` with `module == nil` — these come from test-less targets that coverage
    /// didn't see.
    private static func buildFiles(
        coverageReportDTO: CoverageReportDTO?,
        warningsByFileName: [String: [File.Issue]],
        errorsByFileName: [String: [File.Issue]]
    ) -> [File] {
        // path → builder
        var byPath: [String: FileBuilder] = [:]
        // basename → set of paths (for issue attribution); a basename can map to several
        // distinct files (e.g. helper file in two targets).
        var pathsByBasename: [String: [String]] = [:]

        if let coverageReportDTO {
            for target in coverageReportDTO.targets {
                for fc in target.files {
                    let key = fc.path
                    byPath[key] = FileBuilder(
                        name: fc.name,
                        path: fc.path,
                        module: target.name,
                        coverage: File.Coverage(from: fc)
                    )
                    pathsByBasename[fc.name, default: []].append(fc.path)
                    // Also index by stem (without .swift) so a warning fileName "Foo" can
                    // find "Foo.swift" coverage.
                    if fc.name.hasSuffix(".swift") {
                        let stem = String(fc.name.dropLast(6))
                        pathsByBasename[stem, default: []].append(fc.path)
                    }
                }
            }
        }

        // For files known only from build issues: keyed by basename (no path).
        var byBasename: [String: FileBuilder] = [:]

        func attach(issues: [String: [File.Issue]], asErrors: Bool) {
            for (basename, list) in issues {
                if let paths = pathsByBasename[basename], let firstPath = paths.first {
                    // Attach to every coverage-matched file with that basename — typically one.
                    for path in paths {
                        if asErrors {
                            byPath[path]?.errors.append(contentsOf: list)
                        } else {
                            byPath[path]?.warnings.append(contentsOf: list)
                        }
                    }
                    _ = firstPath  // silence "unused" if future change drops the var
                } else {
                    let key = basename
                    if byBasename[key] == nil {
                        byBasename[key] = FileBuilder(
                            name: basename,
                            path: nil,
                            module: nil,
                            coverage: nil
                        )
                    }
                    if asErrors {
                        byBasename[key]?.errors.append(contentsOf: list)
                    } else {
                        byBasename[key]?.warnings.append(contentsOf: list)
                    }
                }
            }
        }

        attach(issues: warningsByFileName, asErrors: false)
        attach(issues: errorsByFileName, asErrors: true)

        let pathed = byPath.values.map { $0.build() }
        let unpathed = byBasename.values.map { $0.build() }

        return (pathed + unpathed).sorted { lhs, rhs in
            let lk = lhs.path ?? lhs.name
            let rk = rhs.path ?? rhs.name
            return lk < rk
        }
    }

    private struct FileBuilder {
        var name: String
        var path: String?
        var module: String?
        var coverage: File.Coverage?
        var warnings: [File.Issue] = []
        var errors: [File.Issue] = []

        func build() -> File {
            File(
                name: name,
                path: path,
                module: module,
                coverage: coverage,
                warnings: warnings,
                errors: errors
            )
        }
    }

    // MARK: - Suite parsing

    /// Walks `testResultsDTO` and produces a `[testBundleName: [Suite]]` mapping. The
    /// bundle name comes straight from the unit test bundle node — aliasing to a
    /// coverage-target name (e.g. `PeekieTests` → `Peekie`) happens at the call site.
    private static func buildSuites(
        from testResultsDTO: TestResultsDTO
    ) -> [String: [Module.Suite]] {
        var byBundle: [String: [Module.Suite]] = [:]

        for rootNode in testResultsDTO.testNodes where rootNode.nodeType == .testPlan {
            guard let unitTestBundles = rootNode.children else { continue }
            for testNode in unitTestBundles where testNode.nodeType == .unitTestBundle {
                let bundleName = testNode.name
                var suites: [Module.Suite] = []
                for testSuite in testNode.children ?? [] where testSuite.nodeType == .testSuite {
                    guard let nodeIdentifierURL = testSuite.nodeIdentifierURL else { continue }
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
    ) -> Module.Suite {
        var repeatableTests: Set<Module.Suite.RepeatableTest> = []
        let filteredCases = (testSuite.children ?? []).filter { !$0.isMetadata }
        for testCase in filteredCases where testCase.nodeType == .testCase {
            var repeatable = Module.Suite.RepeatableTest(name: testCase.name, tests: [])

            let filteredChildren = (testCase.children ?? []).filter { !$0.isMetadata }
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
        let pathNode: Module.Suite.RepeatableTest.PathNode?
        switch node.nodeType {
        case .device, .arguments, .repetition:
            let result: Module.Suite.RepeatableTest.Test.Status? = {
                guard let r = node.result else { return nil }
                switch r {
                case .passed: return .success
                case .failed: return .failure
                case .skipped: return .skipped
                case .expectedFailure: return .expectedFailure
                }
            }()
            let duration: Measurement<UnitDuration>? = node.durationInSeconds.map {
                .init(value: $0 * 1000, unit: Module.Suite.RepeatableTest.Test.defaultDurationUnit)
            }
            pathNode = .init(
                name: node.name,
                type: .init(from: node.nodeType),
                result: result,
                duration: duration,
                message: node.failureMessage ?? node.skipMessage
            )
        default:
            pathNode = nil
        }

        var newPath = path
        if let pathNode { newPath.append(pathNode) }

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

        let filteredChildren = nodeChildren.filter { !$0.isMetadata }

        if node.nodeType == .arguments {
            let hasRepetitions = filteredChildren.contains { $0.nodeType == .repetition }
            if !hasRepetitions {
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
    private static func aliasTestBundlesToCoverageTargets(
        testBundleNames: Set<String>,
        coverageTargetNames: Set<String>
    ) -> [String: String] {
        // Iterate both sides in sorted order so the chosen alias is deterministic
        // when more than one coverage target satisfies the matching predicate.
        let sortedTargets = coverageTargetNames.sorted()
        var aliases: [String: String] = [:]
        for bundle in testBundleNames.sorted() {
            if coverageTargetNames.contains(bundle) { continue }
            let bundleBase = bundle.replacingOccurrences(of: "Tests", with: "")
            var match: String?
            for target in sortedTargets {
                let targetBase = target.replacingOccurrences(of: "Tests", with: "")
                if target == bundle || targetBase == bundleBase
                    || bundle.contains(target) || target.contains(bundleBase)
                {
                    match = target
                    break
                }
            }
            if let match { aliases[bundle] = match }
        }
        return aliases
    }

    private static func buildModules(
        files: [File],
        suitesByModule: [String: [Module.Suite]],
        coverageReportDTO: CoverageReportDTO?
    ) -> [Module] {
        var moduleNames = Set<String>()
        if let coverageReportDTO {
            moduleNames.formUnion(coverageReportDTO.targets.map(\.name))
        }
        moduleNames.formUnion(suitesByModule.keys)

        return moduleNames.sorted().map { name in
            let moduleFiles = files.filter { $0.module == name }

            let moduleCoverage: Coverage?
            if let target = coverageReportDTO?.targets.first(where: { $0.name == name }),
                target.executableLines > 0
            {
                moduleCoverage = Coverage(
                    coveredLines: target.coveredLines,
                    totalLines: target.executableLines,
                    coverage: target.lineCoverage
                )
            } else {
                moduleCoverage = nil
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

    private static func computeTotalCoverage(
        includeCoverage: Bool,
        coverageReportDTO: CoverageReportDTO?,
        files: [File]
    ) -> Double? {
        guard includeCoverage else { return nil }
        if let lineCoverage = coverageReportDTO?.lineCoverage, lineCoverage > 0 {
            return lineCoverage
        }
        let fileCoverages = files.compactMap(\.coverage)
        guard !fileCoverages.isEmpty else { return nil }
        let total = fileCoverages.reduce(0) { $0 + $1.totalLines }
        let covered = fileCoverages.reduce(0) { $0 + $1.coveredLines }
        return total != 0 ? Double(covered) / Double(total) : 0.0
    }
}
