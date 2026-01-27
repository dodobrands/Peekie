import Foundation
import Logging

extension Report {
    private static let logger = Logger(label: "com.peekie.report")
    /// Initializes a new instance of the `Report` using the provided `xcresultPath`.
    /// The initialization process involves parsing the `.xcresult` file to extract various reports.
    ///
    /// - Parameters:
    ///   - xcresultPath: The file URL of the `.xcresult` file to parse.
    ///   - includeCoverage: Whether to parse and include code coverage data. Defaults to `true`.
    ///   - includeWarnings: Whether to parse and include build warnings. Defaults to `true`.
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
        Self.logger.debug("TestResultsDTO loaded")

        let buildResultsDTO: BuildResultsDTO? =
            includeWarnings ? try await BuildResultsDTO(from: xcresultPath) : nil
        if includeWarnings {
            Self.logger.debug("BuildResultsDTO loaded")
        }

        let coverageReportDTO: CoverageReportDTO? =
            includeCoverage ? try await CoverageReportDTO(from: xcresultPath) : nil
        if includeCoverage {
            Self.logger.debug("CoverageReportDTO loaded")
        }

        // Build a map of file paths to coverage data
        var fileCoverageMap: [String: FileCoverageDTO] = [:]
        if let coverageReportDTO = coverageReportDTO {
            for target in coverageReportDTO.targets {
                for fileCoverage in target.files {
                    // Use both path and name as keys for matching
                    let path = fileCoverage.path
                    let name = fileCoverage.name
                    fileCoverageMap[path] = fileCoverage
                    fileCoverageMap[name] = fileCoverage
                }
            }
        }

        // Parse warnings from build results
        let warningsByFileName: [String: [Report.Module.File.Issue]]
        if let buildResultsDTO = buildResultsDTO {
            warningsByFileName = await Self.parseWarnings(from: buildResultsDTO)
        } else {
            warningsByFileName = [:]
        }

        // Try to get total coverage from xcresult file
        let totalCoverageDTO: TotalCoverageDTO? =
            includeCoverage ? try? await TotalCoverageDTO(from: xcresultPath) : nil

        var modules = Set<Module>()

        // Process test nodes: Test Plan -> Unit test bundle -> Test Suite -> Test Case -> Repetition
        for rootNode in testResultsDTO.testNodes {
            // Root node is "Test Plan", process its children (Unit test bundles)
            guard rootNode.nodeType == .testPlan, let unitTestBundles = rootNode.children else {
                continue
            }

            for testNode in unitTestBundles {
                guard testNode.nodeType == .unitTestBundle else { continue }

                // Extract module name from unit test bundle name (e.g., "PeekieTests")
                let moduleName = testNode.name
                Self.logger.debug(
                    "Processing module",
                    metadata: [
                        "moduleName": "\(moduleName)"
                    ]
                )

                // Find coverage suites for this module
                // Coverage is organized by target (source module), not test module
                // We need to find all coverage suites that belong to this test module's source
                var moduleCoverageFiles: [String: FileCoverageDTO] = [:]
                var matchedTargetCoverage: Report.Coverage? = nil
                if let coverageReportDTO = coverageReportDTO {
                    for target in coverageReportDTO.targets {
                        // Try to match target name with module name
                        // Module name is like "MyPackageTests", target might be "MyPackage"
                        let targetBaseName = target.name.replacingOccurrences(of: "Tests", with: "")
                        let moduleBaseName = moduleName.replacingOccurrences(of: "Tests", with: "")

                        if target.name == moduleName || targetBaseName == moduleBaseName
                            || moduleName.contains(target.name)
                            || target.name.contains(moduleBaseName)
                        {
                            // Store target-level coverage
                            if target.executableLines > 0 {
                                matchedTargetCoverage = Report.Coverage(
                                    coveredLines: target.coveredLines,
                                    totalLines: target.executableLines,
                                    coverage: target.lineCoverage
                                )
                            }

                            for fileCoverage in target.files {
                                // Use suite name (without path) as key
                                moduleCoverageFiles[fileCoverage.name] = fileCoverage
                                // Also use path as key for matching
                                moduleCoverageFiles[fileCoverage.path] = fileCoverage
                            }
                        }
                    }
                }

                var module =
                    modules[moduleName]
                    ?? Report.Module(
                        name: moduleName,
                        suites: [],
                        files: [],
                        coverage: matchedTargetCoverage
                    )

                // Process test suites
                guard let testSuites = testNode.children else { continue }
                for testSuite in testSuites {
                    guard testSuite.nodeType == .testSuite else { continue }

                    // Extract suite name from test suite name (e.g., "ReportTests")
                    let suiteName = testSuite.name

                    Self.logger.debug(
                        "Parsing Test Suite",
                        metadata: [
                            "suiteName": "\(suiteName)",
                            "module": "\(moduleName)",
                        ]
                    )

                    // Store nodeIdentifierURL for fileName computation
                    guard let nodeIdentifierURL = testSuite.nodeIdentifierURL else {
                        // Skip test suites without nodeIdentifierURL (should not happen in practice)
                        Self.logger.debug(
                            "Skipping Test Suite: missing nodeIdentifierURL",
                            metadata: [
                                "suiteName": "\(suiteName)",
                                "module": "\(moduleName)",
                            ]
                        )
                        continue
                    }

                    Self.logger.debug(
                        "Creating Suite from DTO",
                        metadata: [
                            "suiteName": "\(suiteName)",
                            "module": "\(moduleName)",
                            "nodeIdentifierURL": "\(nodeIdentifierURL)",
                        ]
                    )

                    // Try to find coverage for this file by name or path
                    let fileCoverage: Report.Module.File.Coverage?
                    if includeCoverage {
                        // First try by exact suite name
                        if let coverageDTO = fileCoverageMap[suiteName] {
                            fileCoverage = Report.Module.File.Coverage(from: coverageDTO)
                        } else {
                            // Try with .swift extension
                            let suiteNameWithExtension = suiteName + ".swift"
                            if let coverageDTO = fileCoverageMap[suiteNameWithExtension] {
                                fileCoverage = Report.Module.File.Coverage(from: coverageDTO)
                            } else {
                                // Try to match by extracting base name from test suite
                                // Test suite names might be like "ReportTests" but file might be "Report.swift"
                                let baseName = suiteName.replacingOccurrences(of: "Tests", with: "")
                                let possibleNames = [
                                    baseName + ".swift",
                                    baseName,
                                ]
                                var found: FileCoverageDTO? = nil
                                for possibleName in possibleNames {
                                    if let coverageDTO = fileCoverageMap[possibleName] {
                                        found = coverageDTO
                                        break
                                    }
                                }
                                if found == nil {
                                    // Try to find in module-specific coverage files
                                    for (key, coverageDTO) in moduleCoverageFiles {
                                        // Match by exact key or by comparing names (with/without .swift)
                                        let coverageNameWithoutExt =
                                            coverageDTO.name.hasSuffix(".swift")
                                            ? String(coverageDTO.name.dropLast(6))
                                            : coverageDTO.name
                                        if key == suiteName
                                            || key == suiteName + ".swift"
                                            || key.contains(suiteName)
                                            || suiteName == coverageNameWithoutExt
                                            || suiteName == coverageDTO.name
                                        {
                                            found = coverageDTO
                                            break
                                        }
                                    }
                                }
                                if found == nil {
                                    // Try to find by matching suite name in path
                                    for (path, coverageDTO) in fileCoverageMap {
                                        // Match by exact path or by comparing names (with/without .swift)
                                        let coverageNameWithoutExt =
                                            coverageDTO.name.hasSuffix(".swift")
                                            ? String(coverageDTO.name.dropLast(6))
                                            : coverageDTO.name
                                        if path == suiteName
                                            || path == suiteName + ".swift"
                                            || path.contains(suiteName)
                                            || suiteName == coverageNameWithoutExt
                                            || suiteName == coverageDTO.name
                                        {
                                            found = coverageDTO
                                            break
                                        }
                                    }
                                }
                                fileCoverage = found.map { Report.Module.File.Coverage(from: $0) }
                            }
                        }
                    } else {
                        fileCoverage = nil
                    }

                    // Try to get file name from coverage DTO or use suite name
                    var fileName = suiteName
                    if let coverageDTO = fileCoverageMap[suiteName] {
                        fileName = coverageDTO.name
                    } else if let coverageDTO = fileCoverageMap[suiteName + ".swift"] {
                        fileName = coverageDTO.name
                    } else {
                        // Try to find in moduleCoverageFiles
                        for (key, coverageDTO) in moduleCoverageFiles {
                            if key == suiteName || key == suiteName + ".swift" {
                                fileName = coverageDTO.name
                                break
                            }
                        }
                    }

                    // Get or create File with coverage and warnings
                    let fileWarnings: [Report.Module.File.Issue] =
                        includeWarnings
                        ? Self.warningsFor(fileName: fileName, in: warningsByFileName)
                        : []

                    var file = module.files[fileName]
                    if file == nil {
                        file = Report.Module.File(
                            name: fileName,
                            warnings: fileWarnings,
                            coverage: fileCoverage
                        )
                        module.files.insert(file!)
                    } else {
                        // Merge warnings if file already exists
                        if includeWarnings && !fileWarnings.isEmpty {
                            file!.warnings = Self.mergeWarnings(file!.warnings, fileWarnings)
                        }
                    }

                    // Get existing suite or create new one
                    var suite: Report.Module.Suite
                    if let existingSuite = module.suites[suiteName] {
                        Self.logger.debug(
                            "Using existing Suite",
                            metadata: [
                                "suiteName": "\(suiteName)",
                                "module": "\(moduleName)",
                            ]
                        )
                        suite = existingSuite
                    } else {
                        Self.logger.debug(
                            "Created new Suite",
                            metadata: [
                                "suiteName": "\(suiteName)",
                                "module": "\(moduleName)",
                            ]
                        )
                        suite = .init(
                            name: suiteName,
                            nodeIdentifierURL: nodeIdentifierURL,
                            repeatableTests: []
                        )
                    }

                    // Process test cases
                    guard let testCases = testSuite.children else { continue }
                    for testCase in testCases {
                        guard testCase.nodeType == .testCase else { continue }

                        let testName = testCase.name
                        var repeatableTest =
                            suite.repeatableTests[testName]
                            ?? Report.Module.Suite.RepeatableTest(
                                name: testName,
                                tests: []
                            )

                        // Filter out metadata nodes from test case children
                        let filteredTestCaseChildren = (testCase.children ?? []).filter {
                            !$0.isMetadata
                        }

                        // Process test case children and create Test objects with paths
                        func processNode(
                            _ node: TestResultsDTO.TestNode,
                            path: [Report.Module.Suite.RepeatableTest.PathNode],
                            testCase: TestResultsDTO.TestNode
                        ) throws {
                            // Check if this node should be added to path
                            let pathNode: Report.Module.Suite.RepeatableTest.PathNode?
                            switch node.nodeType {
                            case .device, .arguments, .repetition:
                                // Convert result from DTO to Test.Status
                                let result: Report.Module.Suite.RepeatableTest.Test.Status? = {
                                    guard let dtoResult = node.result else { return nil }
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
                                }()

                                // Convert duration from DTO
                                let duration: Measurement<UnitDuration>? = {
                                    guard let durationSeconds = node.durationInSeconds else {
                                        return nil
                                    }
                                    return .init(
                                        value: durationSeconds * 1000,
                                        unit: Report.Module.Suite.RepeatableTest.Test
                                            .defaultDurationUnit
                                    )
                                }()

                                // Extract message from DTO
                                let message = node.failureMessage ?? node.skipMessage

                                pathNode = Report.Module.Suite.RepeatableTest.PathNode(
                                    name: node.name,
                                    type: .init(from: node.nodeType),
                                    result: result,
                                    duration: duration,
                                    message: message
                                )
                            default:
                                pathNode = nil
                            }

                            var newPath = path
                            if let pathNode = pathNode {
                                newPath.append(pathNode)
                            }

                            // If this is a repetition node, create test and stop recursion
                            if node.nodeType == .repetition {
                                let test = try Report.Module.Suite.RepeatableTest.Test(
                                    from: node,
                                    path: newPath,
                                    testCaseName: testCase.name,
                                    testCase: testCase
                                )
                                repeatableTest.tests.append(test)
                                return
                            }

                            guard let nodeChildren = node.children else {
                                // Leaf node - create test if it's an arguments node without children
                                if node.nodeType == .arguments {
                                    let test = Report.Module.Suite.RepeatableTest.Test(
                                        from: node,
                                        path: newPath,
                                        testCase: testCase
                                    )
                                    repeatableTest.tests.append(test)
                                }
                                return
                            }

                            // Filter out metadata nodes from node children
                            let filteredNodeChildren = nodeChildren.filter { !$0.isMetadata }

                            // If this is an arguments node, check if it has repetitions
                            if node.nodeType == .arguments {
                                let hasRepetitions = filteredNodeChildren.contains {
                                    $0.nodeType == .repetition
                                }
                                if !hasRepetitions {
                                    // Arguments without repetitions - create test and stop recursion
                                    let test = Report.Module.Suite.RepeatableTest.Test(
                                        from: node,
                                        path: newPath,
                                        testCase: testCase
                                    )
                                    repeatableTest.tests.append(test)
                                    return
                                }
                                // Arguments with repetitions - continue recursion to process repetitions
                            }

                            // Recursively process children (already filtered)
                            for child in filteredNodeChildren {
                                try processNode(child, path: newPath, testCase: testCase)
                            }
                        }

                        // Start processing from filtered test case children
                        for child in filteredTestCaseChildren {
                            try processNode(child, path: [], testCase: testCase)
                        }

                        // If no tests were created (no children or only metadata), create test from test case itself
                        if repeatableTest.tests.isEmpty {
                            let test = Report.Module.Suite.RepeatableTest.Test(from: testCase)
                            repeatableTest.tests.append(test)
                        }

                        suite.repeatableTests.update(with: repeatableTest)
                    }

                    module.suites.update(with: suite)
                }

                // Update module in set, preserving coverage
                if let existingModule = modules[moduleName] {
                    modules.remove(existingModule)
                }
                modules.insert(module)
            }
        }

        // Add all suites with coverage to modules, even if they don't have test suites
        if let coverageReportDTO = coverageReportDTO {
            for target in coverageReportDTO.targets {
                // Create coverage from target-level data if available
                let targetCoverage: Report.Coverage? = {
                    guard target.executableLines > 0 else { return nil }
                    return Report.Coverage(
                        coveredLines: target.coveredLines,
                        totalLines: target.executableLines,
                        coverage: target.lineCoverage
                    )
                }()

                // Try to find existing module by target name or create a new one
                // Target name might be like "MyPackage", module might be "MyPackageTests"
                var moduleName = target.name
                var existingModule = modules[moduleName]

                // If not found, try to find module with "Tests" suffix
                if existingModule == nil {
                    let moduleNameWithTests = target.name + "Tests"
                    if let foundModule = modules[moduleNameWithTests] {
                        existingModule = foundModule
                        moduleName = moduleNameWithTests
                    }
                }

                // Start with existing module suites and files or empty sets
                let moduleSuites = existingModule?.suites ?? Set<Report.Module.Suite>()
                var moduleFiles = existingModule?.files ?? Set<Report.Module.File>()

                // Determine module coverage: use target coverage if module doesn't have one, or keep existing
                let moduleCoverage = existingModule?.coverage ?? targetCoverage

                // Add all coverage files to this module
                for fileCoverageDTO in target.files {
                    let coverage = Report.Module.File.Coverage(from: fileCoverageDTO)
                    // Use the name as it appears in xcresult
                    let fileName = fileCoverageDTO.name

                    // Get warnings for this file
                    let fileWarnings: [Report.Module.File.Issue] =
                        includeWarnings
                        ? Self.warningsFor(fileName: fileName, in: warningsByFileName)
                        : []

                    // Create or update File with coverage and warnings
                    var file = moduleFiles[fileName]
                    if file == nil {
                        file = Report.Module.File(
                            name: fileName,
                            warnings: fileWarnings,
                            coverage: coverage
                        )
                        moduleFiles.insert(file!)
                    } else {
                        // Merge warnings if file already exists
                        if includeWarnings && !fileWarnings.isEmpty {
                            file!.warnings = Self.mergeWarnings(file!.warnings, fileWarnings)
                        }
                    }
                }

                // Remove old module if it existed and add updated one
                if let oldModule = existingModule {
                    modules.remove(oldModule)
                }

                // Create or update module with all suites, files and coverage
                let updatedModule = Report.Module(
                    name: moduleName, suites: moduleSuites, files: moduleFiles,
                    coverage: moduleCoverage)
                modules.insert(updatedModule)
            }
        }

        // Use total coverage from xcresult file if available, otherwise calculate from suites
        let totalCoverage: Double? =
            includeCoverage
            ? {
                if let totalCoverageDTO = totalCoverageDTO {
                    let lineCoverage = totalCoverageDTO.lineCoverage
                    // totalCoverageDTO is available; still allow fallback in case of zeroed data
                    if lineCoverage > 0 {
                        return lineCoverage
                    }
                }

                let fileCoverages = modules.flatMap { $0.files }.compactMap { $0.coverage }
                guard !fileCoverages.isEmpty else { return nil }
                let totalLines = fileCoverages.reduce(0) { $0 + $1.totalLines }
                let totalCoveredLines = fileCoverages.reduce(0) { $0 + $1.coveredLines }
                return totalLines != 0 ? Double(totalCoveredLines) / Double(totalLines) : 0.0
            }() : nil

        self.modules = modules
        self.coverage = totalCoverage

        Self.logger.debug(
            "Report initialization completed",
            metadata: [
                "modulesCount": "\(modules.count)",
                "totalCoverage": totalCoverage.map { "\($0)" } ?? "nil",
            ]
        )
    }
}
