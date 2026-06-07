import Foundation
import Logging
import XMLCoder

// MARK: - SonarFormatter

/// Formatter that generates SonarQube Generic Test Execution XML format
///
/// This formatter converts test results into XML format compatible with SonarQube's
/// Generic Test Data import feature, enabling test result visualization in SonarQube dashboards.
///
/// - Note: Requires a testsPath directory to map test suite names to actual file paths,
///   as xcresult files only contain suite URLs without file paths.
public final class SonarFormatter {
    // MARK: Lifecycle

    /// Creates a new SonarQube formatter instance
    public init() {}

    // MARK: Public

    /// Formats a report into SonarQube Generic Test Execution XML
    /// - Parameters:
    ///   - report: The parsed test report to format
    ///   - testsPath: Directory containing test source files for file path resolution
    /// - Returns: XML string in SonarQube Generic Test Execution format
    /// - Throws: Error if file path resolution fails or XML encoding fails
    public func format(
        report: Report,
        testsPath: URL
    ) throws
        -> String
    {
        let fsIndex = try FSIndex(path: testsPath)
        let sonarFiles = collectFiles(report: report, fsIndex: fsIndex)
        return try encode(TestExecutions(file: sonarFiles))
    }

    // MARK: Private

    /// Flatten a suite tree into all suites (root + nested) so each maps to its
    /// own source file in the SonarQube XML output.
    private static func flatten(_ suite: Report.Module.Suite) -> [Report.Module.Suite] {
        [suite] + suite.nestedSuites.flatMap { flatten($0) }
    }

    private func collectFiles(report: Report, fsIndex: FSIndex) -> [XMLFile] {
        var filesByPath = [String: [TestCase]]()
        var pathsByNode = [String: String]()

        for module in report.modules.sorted(by: { $0.name < $1.name }) {
            // Root-level @Tests: no enclosing suite means no filesystem anchor —
            // SonarQube needs a file path per <file> element, so we can't surface
            // these tests in the XML output. They still appear in the List/JSON
            // formatters which don't require path resolution.

            let flatSuites = module.suites.flatMap { Self.flatten($0) }
            for suite in flatSuites.sorted(by: { $0.fullPath < $1.fullPath }) {
                guard suite.repeatableTests.isEmpty == false else {
                    continue
                }
                guard let path = resolvePath(for: suite, fsIndex: fsIndex, cache: &pathsByNode)
                else {
                    continue
                }

                let testCases = TestCase.cases(from: suite)
                filesByPath[path, default: []].append(contentsOf: testCases)
            }
        }

        return filesByPath
            .map { path, testCases in XMLFile(path: path, testCase: testCases) }
            .sorted { $0.path < $1.path }
    }

    private func resolvePath(
        for suite: Report.Module.Suite,
        fsIndex: FSIndex,
        cache: inout [String: String]
    )
        -> String?
    {
        if let cached = cache[suite.nodeIdentifierURL] {
            return cached
        }
        guard let url = URL(string: suite.nodeIdentifierURL),
              let found = fsIndex.classes[url.lastPathComponent]
        else {
            return nil
        }

        cache[suite.nodeIdentifierURL] = found
        return found
    }

    private func encode(_ dto: TestExecutions) throws -> String {
        let encoder = XMLEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(dto, withRootKey: "testExecutions")
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - TestExecutions

//
// Type names are PascalCase as Swift convention requires. The XML element
// names are mapped via `CodingKeys` raw values (`testExecutions`, `file`,
// `testCase`, `skipped`, `failure`) — that's the SonarQube schema and what
// the encoder writes.

private struct TestExecutions: Encodable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
        case version
        case file
    }

    let version = 1
    let file: [XMLFile]

    static func nodeEncoding(for key: CodingKey) -> XMLEncoder.NodeEncoding {
        switch key {
        case CodingKeys.version:
            .attribute
        default:
            .element
        }
    }
}

// MARK: - XMLFile

private struct XMLFile: Encodable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
        case path
        case testCase
    }

    let path: String
    let testCase: [TestCase]

    static func nodeEncoding(for key: CodingKey) -> XMLEncoder.NodeEncoding {
        switch key {
        case CodingKeys.path:
            .attribute
        default:
            .element
        }
    }
}

// MARK: - TestCase

private struct TestCase: Encodable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
        case name
        case duration
        case skipped
        case failure
    }

    let name: String
    let duration: Int
    let skipped: Skipped?
    let failure: Failure?

    static func nodeEncoding(for key: CodingKey) -> XMLEncoder.NodeEncoding {
        switch key {
        case CodingKeys.name,
             CodingKeys.duration:
            .attribute
        default:
            .element
        }
    }
}

// MARK: - Skipped

private struct Skipped: Encodable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
        case message
    }

    let message: String

    static func nodeEncoding(for key: CodingKey) -> XMLEncoder.NodeEncoding {
        switch key {
        case CodingKeys.message:
            .attribute
        default:
            .element
        }
    }
}

// MARK: - Failure

private struct Failure: Encodable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
        case message
    }

    let message: String

    static func nodeEncoding(for key: CodingKey) -> XMLEncoder.NodeEncoding {
        switch key {
        case CodingKeys.message:
            .attribute
        default:
            .element
        }
    }
}

extension TestCase {
    init(_ test: Report.Module.Suite.RepeatableTest.Test, qualifiedName: String? = nil) {
        self.init(
            name: qualifiedName ?? test.name,
            duration: Int(test.duration.converted(to: .milliseconds).value),
            skipped: test.status == .skipped ? test.message.map { .init(message: $0) } : nil,
            failure: test.status == .failure ? test.message.map { .init(message: $0) } : nil
        )
    }
}

private extension TestCase {
    static func cases(from suite: Report.Module.Suite) -> [Self] {
        var testCases = [Self]()

        for repeatableTest in suite.repeatableTests.sorted(by: { $0.name < $1.name }) {
            // Use merged tests which already handle repetitions and optionally devices
            let mergedTests = repeatableTest.mergedTests(filterDevice: false)

            // Qualify the test name with the suite's full path so nested suites
            // can share a source file without collisions (XMLEncoder handles
            // special-character escaping on attribute values).
            for test in mergedTests {
                let qualifiedName = "\(suite.fullPath) / \(test.name)"
                testCases.append(Self(test, qualifiedName: qualifiedName))
            }
        }

        return testCases
    }
}
