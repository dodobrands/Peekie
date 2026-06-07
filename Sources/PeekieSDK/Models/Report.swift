import Foundation

// MARK: - Report

/// Parsed report from an `.xcresult` file.
///
/// `files` is the primary index — every file we have any signal about (coverage,
/// warnings, errors) lives here exactly once, regardless of which target it
/// belongs to. `modules` is a projection over `files` for the subset where a
/// target name is known. Build issues with no module signal (`xcresulttool`
/// doesn't currently surface `producingTarget` for them) still surface — they
/// appear in `files` with `File.module == nil` and are reachable via
/// `Report.warnings` / `Report.errors`.
public struct Report {
    // MARK: Lifecycle

    /// Creates a `Report` from already-parsed pieces. The async
    /// `Report(xcresultPath:…)` initializer is the usual entry point;
    /// this memberwise init is for tests and test helpers.
    public init(
        files: [File],
        modules: [Module],
        coverage: Double?
    ) {
        self.files = files
        self.modules = modules
        self.coverage = coverage
    }

    // MARK: Public

    /// Every file the bundle has any signal about (coverage, warnings, errors).
    public let files: [File]

    /// Module projection — one entry per target name we could identify
    /// (from coverage or from tests). Files whose target is unknown are
    /// **not** represented here; reach them via `files`.
    public let modules: [Module]

    /// Total code coverage percentage (0.0 to 1.0).
    /// - Note: Read directly from xcresult coverage data (not calculated from files).
    public let coverage: Double?

    /// All warnings from all files in this report.
    public var warnings: [File.Issue] {
        files.flatMap(\.warnings)
    }

    /// All errors from all files in this report.
    public var errors: [File.Issue] {
        files.flatMap(\.errors)
    }
}

public extension Report {
    /// A source file with coverage, warnings, and errors information.
    ///
    /// `File` is the primary entity in the model — every data source xcresult
    /// emits identifies files by `sourceURL` or coverage path. `module` is the
    /// only optional identity field: build-issue records don't carry target
    /// ownership, so a file known only from `warnings[]` / `errors[]` has
    /// `module == nil`. Identity (hash, equality) is `path ?? name`: two files
    /// with the same basename but different paths are distinct.
    struct File: Hashable {
        // MARK: Lifecycle

        public init(
            name: String,
            path: String? = nil,
            module: String? = nil,
            coverage: Coverage? = nil,
            warnings: [Issue] = [],
            errors: [Issue] = []
        ) {
            self.name = name
            self.path = path
            self.module = module
            self.coverage = coverage
            self.warnings = warnings
            self.errors = errors
        }

        // MARK: Public

        /// Basename of the file (e.g., "Report.swift").
        public let name: String

        /// Absolute path when xcresult provided one (coverage and warnings/errors do).
        public let path: String?

        /// Owning target name when known. `nil` for files known only from
        /// build issues (xcresult doesn't emit `producingTarget` for those).
        public let module: String?

        /// Code coverage for this file when present.
        public let coverage: Coverage?

        /// Build warnings on this file.
        public let warnings: [Issue]

        /// Build errors on this file.
        public let errors: [Issue]

        public static func ==(lhs: Self, rhs: Self) -> Bool {
            (lhs.path ?? lhs.name) == (rhs.path ?? rhs.name)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(path ?? name)
        }
    }

    /// Projection over `Report.files` grouped by target name.
    ///
    /// `Module` is built from coverage targets and test bundles — the two data
    /// sources xcresult emits that name a target. A module's `files` slice is
    /// every `Report.files` entry whose `File.module` matches; `suites` is the
    /// tests xcresult reported for that target.
    struct Module: Hashable {
        // MARK: Lifecycle

        public init(
            name: String,
            files: [File] = [],
            coverage: Coverage? = nil,
            suites: [Suite] = []
        ) {
            self.name = name
            self.files = files
            self.coverage = coverage
            self.suites = suites
        }

        // MARK: Public

        /// Target name (e.g., "Bonuses", "PeekieTests").
        public let name: String

        /// Files in this report whose `File.module == self.name`.
        public let files: [File]

        /// Target-level coverage when xcresult reported one.
        public let coverage: Coverage?

        /// Test suites this target ran.
        public let suites: [Suite]

        /// All warnings from all files in this module.
        public var warnings: [File.Issue] {
            files.flatMap(\.warnings)
        }

        /// All errors from all files in this module.
        public var errors: [File.Issue] {
            files.flatMap(\.errors)
        }

        public static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.name == rhs.name
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
    }

    /// Aggregate code coverage at the module or report scope.
    struct Coverage: Equatable {
        // MARK: Lifecycle

        public init(coveredLines: Int, totalLines: Int, coverage: Double) {
            self.coveredLines = coveredLines
            self.totalLines = totalLines
            self.coverage = coverage
        }

        // MARK: Public

        public let coveredLines: Int
        public let totalLines: Int
        public let coverage: Double
    }
}

public extension Report.File {
    /// Code coverage information for a specific file.
    struct Coverage: Equatable {
        // MARK: Lifecycle

        public init(coveredLines: Int, totalLines: Int, coverage: Double) {
            self.coveredLines = coveredLines
            self.totalLines = totalLines
            self.coverage = coverage
        }

        init(from dto: FileCoverageDTO) {
            coveredLines = dto.coveredLines
            totalLines = dto.executableLines
            coverage = dto.lineCoverage
        }

        // MARK: Public

        public let coveredLines: Int
        public let totalLines: Int
        public let coverage: Double
    }

    /// A build issue (warning or error) associated with a file.
    struct Issue: Equatable, Sendable {
        // MARK: Lifecycle

        public init(type: IssueType, message: String, location: Location? = nil) {
            self.type = type
            self.message = message
            self.location = location
        }

        // MARK: Public

        /// Source range inside a file. `startLine` is the minimum guarantee;
        /// other three fields are independently optional because `xcresulttool`
        /// is not contractually obligated to emit all of them.
        public struct Location: Equatable, Sendable, Codable {
            // MARK: Lifecycle

            public init(
                startLine: Int,
                startColumn: Int? = nil,
                endLine: Int? = nil,
                endColumn: Int? = nil
            ) {
                self.startLine = startLine
                self.startColumn = startColumn
                self.endLine = endLine
                self.endColumn = endColumn
            }

            // MARK: Public

            public let startLine: Int
            public let startColumn: Int?
            public let endLine: Int?
            public let endColumn: Int?
        }

        /// Types of build issues that can be reported.
        ///
        /// The set of `issueType` values emitted by `xcresulttool` is open —
        /// Apple adds new typed diagnostics in newer Xcode releases. Use
        /// `.unknown(_)` for forward compatibility; the raw string is preserved
        /// verbatim.
        public enum IssueType: Equatable, Sendable {
            case swiftCompilerWarning
            case swiftCompilerError
            case deprecatedDeclaration
            case noUsage
            case unknown(String)
        }

        public let type: IssueType
        public let message: String

        /// Source location in the file when xcresult provided one.
        /// `nil` for project-level issues or when the `sourceURL` fragment has
        /// no `StartingLineNumber`.
        public let location: Location?
    }
}

public extension Report.File.Issue.IssueType {
    /// Maps an Apple-emitted `issueType` string to a typed case. Unrecognized
    /// values fall through to `.unknown(raw)`, preserving the original string.
    init(rawValue: String) {
        switch rawValue {
        case "Swift Compiler Warning":
            self = .swiftCompilerWarning
        case "Swift Compiler Error":
            self = .swiftCompilerError
        case "DeprecatedDeclaration":
            self = .deprecatedDeclaration
        case "No-usage":
            self = .noUsage
        default:
            self = .unknown(rawValue)
        }
    }

    /// The raw `issueType` string as emitted by `xcresulttool`. Round-trips
    /// through `init(rawValue:)`.
    var rawValue: String {
        switch self {
        case .swiftCompilerWarning:
            "Swift Compiler Warning"
        case .swiftCompilerError:
            "Swift Compiler Error"
        case .deprecatedDeclaration:
            "DeprecatedDeclaration"
        case .noUsage:
            "No-usage"
        case .unknown(let raw):
            raw
        }
    }
}

// MARK: - Report.File.Issue.IssueType + Codable

extension Report.File.Issue.IssueType: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(rawValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Report.Module.Suite

public extension Report.Module {
    /// A test suite containing a group of related tests
    struct Suite: Hashable {
        // MARK: Lifecycle

        public init(
            name: String,
            nodeIdentifierURL: String,
            repeatableTests: Set<RepeatableTest> = []
        ) {
            self.name = name
            self.nodeIdentifierURL = nodeIdentifierURL
            self.repeatableTests = repeatableTests
        }

        // MARK: Public

        /// Name of the test suite (e.g., "ReportTests")
        public let name: String

        /// URL identifier from the test node in xcresult JSON.
        /// Examples:
        /// - Test Suite: `"test://com.apple.xcode/Module/ModuleTests/SuiteTests"`
        /// - Test Case: `"test://com.apple.xcode/Module/ModuleTests/SuiteTests/test_example"`
        /// - Unit test bundle: `"test://com.apple.xcode/Module/ModuleTests"`
        /// Format: `test://com.apple.xcode/<Module>/<Bundle>/<Suite>/<TestCase>`
        public let nodeIdentifierURL: String

        /// Set of repeatable tests in this suite
        public internal(set) var repeatableTests: Set<RepeatableTest>

        public static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.name == rhs.name
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
    }
}
