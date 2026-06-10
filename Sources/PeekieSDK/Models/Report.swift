import Foundation

// MARK: - Report

/// Parsed report from an `.xcresult` file.
///
/// `files` is the primary index — every file we have any signal about (coverage,
/// warnings, errors) lives here exactly once, regardless of which target it
/// belongs to. `modules` is a thin handle list: one ``Module`` per identifiable
/// target name. Module-scoped data (files, coverage, suites, root-level tests)
/// lives on `Report` keyed by target name and is reached via the `…(in:)`
/// lookups. Build issues with no module signal (`xcresulttool` doesn't currently
/// surface `producingTarget` for them) still surface — they appear in `files`
/// with `File.module == nil` and are reachable via `Report.warnings` /
/// `Report.errors`.
public struct Report {
    // MARK: Lifecycle

    /// Creates a `Report` from already-parsed pieces. The async
    /// `Report(xcresultPath:…)` initializer is the usual entry point;
    /// this memberwise init is for tests and test helpers.
    public init(
        files: [File],
        modules: [Module],
        coverage: Double?,
        coverageByModule: [String: Coverage] = [:],
        suitesByModule: [String: [Module.Suite]] = [:],
        rootLevelTestsByModule: [String: Set<Module.Suite.RepeatableTest>] = [:]
    ) {
        self.files = files
        self.modules = modules
        self.coverage = coverage
        self.coverageByModule = coverageByModule
        self.suitesByModule = suitesByModule
        self.rootLevelTestsByModule = rootLevelTestsByModule
    }

    // MARK: Public

    /// Every file the bundle has any signal about (coverage, warnings, errors).
    public let files: [File]

    /// One handle per identifiable target name (from coverage or from tests).
    /// Files whose target is unknown are **not** represented here; reach them
    /// via `files`. Module-scoped data is on `Report` — see ``files(in:)``,
    /// ``coverage(of:)``, ``suites(in:)``, ``rootLevelTests(in:)``.
    public let modules: [Module]

    /// Total code coverage percentage (0.0 to 1.0).
    /// - Note: Read directly from xcresult coverage data (not calculated from files).
    public let coverage: Double?

    /// Target-level aggregate coverage keyed by ``Module/name``. Empty entries
    /// are omitted (a target with `executableLines == 0` is dropped at parse
    /// time, matching the legacy `Module.coverage == nil` shape).
    public let coverageByModule: [String: Coverage]

    /// Top-level test suites keyed by ``Module/name``. Empty list = the target
    /// had no tests (or `includeTests: false` at parse time).
    public let suitesByModule: [String: [Module.Suite]]

    /// Swift Testing root-level `@Test` functions keyed by ``Module/name``.
    /// Empty set = no `@Test`s declared outside `@Suite` types (or
    /// `includeTests: false`).
    public let rootLevelTestsByModule: [String: Set<Module.Suite.RepeatableTest>]

    /// All warnings from all files in this report.
    public var warnings: [File.Issue] {
        files.flatMap(\.warnings)
    }

    /// All errors from all files in this report.
    public var errors: [File.Issue] {
        files.flatMap(\.errors)
    }

    /// Files whose ``File/module`` matches the given module's `name`.
    /// Order matches `files` (sorted by path-or-name at parse time).
    public func files(in module: Module) -> [File] {
        files.filter { $0.module == module.name }
    }

    /// Target-level aggregate coverage for the given module, when xcresult
    /// reported one. Returns `nil` for targets with no executable lines, or
    /// for handles whose name isn't in the report (callers shouldn't see
    /// orphan handles in practice — `modules` is built only from names we
    /// observe).
    public func coverage(of module: Module) -> Coverage? {
        coverageByModule[module.name]
    }

    /// Top-level test suites this target ran. Nested suites live inside their
    /// parents via ``Module/Suite/nestedSuites`` — only the outermost suites
    /// appear here.
    public func suites(in module: Module) -> [Module.Suite] {
        suitesByModule[module.name] ?? []
    }

    /// Swift Testing `@Test` functions declared at the bundle root, i.e.
    /// outside any `@Suite` type. Empty for legacy `XCTest`-only bundles,
    /// where every test is wrapped in an `XCTestCase` subclass that surfaces
    /// as a `Test Suite` node.
    public func rootLevelTests(in module: Module) -> Set<Module.Suite.RepeatableTest> {
        rootLevelTestsByModule[module.name] ?? []
    }

    /// All warnings from files belonging to the given module.
    public func warnings(in module: Module) -> [File.Issue] {
        files(in: module).flatMap(\.warnings)
    }

    /// All errors from files belonging to the given module.
    public func errors(in module: Module) -> [File.Issue] {
        files(in: module).flatMap(\.errors)
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

    /// Thin handle to a target named by xcresult (coverage or test bundle).
    ///
    /// `Module` carries only the target name. File listings, target-level
    /// coverage, suites and root-level tests live on ``Report`` as dictionaries
    /// keyed by `name`. Use the report-side lookups to reach them:
    /// ``Report/files(in:)``, ``Report/coverage(of:)``, ``Report/suites(in:)``,
    /// ``Report/rootLevelTests(in:)``, ``Report/warnings(in:)``,
    /// ``Report/errors(in:)``.
    ///
    /// This shape replaces the 5.x `Module` that materialized `files` etc. as
    /// stored properties — that design duplicated `File` values across
    /// `Report.files` and `Module.files`, made `report.warnings +
    /// modules.flatMap(\.warnings)` double-count, and burdened snapshots with
    /// two copies of every file's issues.
    struct Module: Hashable {
        // MARK: Lifecycle

        public init(name: String) {
            self.name = name
        }

        // MARK: Public

        /// Target name (e.g., "Bonuses", "PeekieTests").
        public let name: String

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
            case actorIsolatedCall
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
        case "ActorIsolatedCall":
            self = .actorIsolatedCall
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
        case .actorIsolatedCall:
            "ActorIsolatedCall"
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
            fullPath: String? = nil,
            repeatableTests: Set<RepeatableTest> = [],
            nestedSuites: [Self] = []
        ) {
            self.name = name
            self.fullPath = fullPath ?? name
            self.nodeIdentifierURL = nodeIdentifierURL
            self.repeatableTests = repeatableTests
            self.nestedSuites = nestedSuites
        }

        // MARK: Public

        /// Short name of the test suite (e.g., "InnerSuite")
        public let name: String

        /// Fully qualified suite path joined by `" / "` from the outermost suite to
        /// `self`. For top-level suites this equals `name`; for nested suites it is
        /// e.g. `"OuterSuite / InnerSuite / DeeplyNestedSuite"`. Used for
        /// human-facing identification and as the equality / hash key, so two
        /// suites named `InnerSuite` under different parents stay distinct.
        public let fullPath: String

        /// URL identifier from the test node in xcresult JSON.
        /// Examples:
        /// - Test Suite: `"test://com.apple.xcode/Module/ModuleTests/SuiteTests"`
        /// - Test Case: `"test://com.apple.xcode/Module/ModuleTests/SuiteTests/test_example"`
        /// - Unit test bundle: `"test://com.apple.xcode/Module/ModuleTests"`
        /// Format: `test://com.apple.xcode/<Module>/<Bundle>/<Suite>/<TestCase>`
        public let nodeIdentifierURL: String

        /// Set of repeatable tests directly inside this suite (excluding tests of
        /// any nested `@Suite`-typed child).
        public internal(set) var repeatableTests: Set<RepeatableTest>

        /// Suites declared inside this suite (nested `@Suite` types). Order matches
        /// the order returned by `xcresulttool`; in practice this is declaration
        /// order from the source file. Empty when this suite has no nested suites.
        public let nestedSuites: [Self]

        public static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.fullPath == rhs.fullPath
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(fullPath)
        }
    }
}
