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

        logger.debug(
            "FSIndex created",
            metadata: [
                "testsPath": "\(testsPath.path)",
                "classesCount": "\(fsIndex.classes.count)",
            ]
        )

        // Group files by actual file path (multiple test suites can be in one file)
        var filesByPath = [String: [TestCase]]()
        // Track paths by nodeIdentifierURL (full node identifier)
        var pathsByNode = [String: String]()

        for file in report.modules.flatMap(\.suites).sorted(by: { $0.name < $1.name }) {
            // Skip files that don't have any tests (coverage-only files)
            guard file.repeatableTests.isEmpty == false else {
                logger.debug(
                    "Skipping Suite: no tests",
                    metadata: [
                        "suiteName": "\(file.name)",
                        "nodeIdentifierURL": "\(file.nodeIdentifierURL)",
                    ]
                )
                continue
            }

            // Extract class name from nodeIdentifierURL (lastPathComponent)
            guard let url = URL(string: file.nodeIdentifierURL) else {
                logger.debug(
                    "Skipping Suite: cannot parse nodeIdentifierURL as URL",
                    metadata: [
                        "suiteName": "\(file.name)",
                        "nodeIdentifierURL": "\(file.nodeIdentifierURL)",
                    ]
                )
                continue
            }

            let className = url.lastPathComponent

            logger.debug(
                "Looking up Suite in FSIndex",
                metadata: [
                    "suiteName": "\(file.name)",
                    "nodeIdentifierURL": "\(file.nodeIdentifierURL)",
                    "className": "\(className)",
                ]
            )

            // Check if we already have path for this nodeIdentifierURL
            let path: String
            if let cachedPath = pathsByNode[file.nodeIdentifierURL] {
                path = cachedPath
                logger.debug(
                    "Using cached path for nodeIdentifierURL",
                    metadata: [
                        "suiteName": "\(file.name)",
                        "nodeIdentifierURL": "\(file.nodeIdentifierURL)",
                        "path": "\(path)",
                    ]
                )
            } else if let foundPath = fsIndex.classes[className] {
                path = foundPath
                pathsByNode[file.nodeIdentifierURL] = path
                logger.debug(
                    "Found Suite in FSIndex",
                    metadata: [
                        "suiteName": "\(file.name)",
                        "nodeIdentifierURL": "\(file.nodeIdentifierURL)",
                        "className": "\(className)",
                        "path": "\(path)",
                    ]
                )
            } else {
                logger.debug(
                    "Skipping Suite: not found in FSIndex",
                    metadata: [
                        "suiteName": "\(file.name)",
                        "nodeIdentifierURL": "\(file.nodeIdentifierURL)",
                        "className": "\(className)",
                        "availableClasses":
                            "\(Array(fsIndex.classes.keys.sorted().prefix(10)).joined(separator: ", "))",
                    ]
                )
                continue
            }

            // Extract test cases from this file
            let testCases = TestCase.cases(from: file)

            // Merge test cases by file path
            if filesByPath[path] != nil {
                filesByPath[path]?.append(contentsOf: testCases)
            } else {
                filesByPath[path] = testCases
            }
        }

        // Create file entries from grouped test cases
        let sonarFiles = filesByPath.map { path, testCases in
            XMLFile(path: path, testCase: testCases)
        }
        .sorted { $0.path < $1.path }
        let dto = TestExecutions(file: sonarFiles)

        let encoder = XMLEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(dto, withRootKey: "testExecutions")
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Private

    private let logger: Logger = .init(label: "com.peekie.formatter.sonar")
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
    init(_ test: Report.Module.Suite.RepeatableTest.Test) {
        self.init(
            name: test.name,
            duration: Int(test.duration.converted(to: .milliseconds).value),
            skipped: test.status == .skipped ? test.message.map { .init(message: $0) } : nil,
            failure: test.status == .failure ? test.message.map { .init(message: $0) } : nil
        )
    }
}

private extension TestCase {
    static func cases(from file: Report.Module.Suite) -> [Self] {
        var testCases = [Self]()

        for repeatableTest in file.repeatableTests.sorted(by: { $0.name < $1.name }) {
            // Use merged tests which already handle repetitions and optionally devices
            let mergedTests = repeatableTest.mergedTests(filterDevice: false)

            // Output each merged test separately
            for test in mergedTests {
                testCases.append(Self(test))
            }
        }

        return testCases
    }
}
