import Foundation
import Logging
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// MARK: - AttachmentPolicy

/// Controls whether `Report` exports and surfaces test attachments.
///
/// `xcresulttool export attachments` writes binary attachment files plus a
/// `manifest.json` to a directory. With `.skip` (default), nothing is exported
/// and `Report.Module.Suite.RepeatableTest.Test.attachments` is empty
/// everywhere. With `.extractTo(url)`, files are written under `url` and each
/// matching test gets its attachments wired up.
public enum AttachmentPolicy: Sendable {
    /// Do not run `xcresulttool export attachments`; tests carry no attachments.
    case skip

    /// Export attachments into the supplied directory. Caller owns the directory
    /// lifetime (create + cleanup).
    ///
    /// When `testID` is non-nil, `xcresulttool` is invoked with
    /// `--test-id <id>`, scoping both the manifest and the on-disk file set
    /// to that single test's attachments. The id is the bare suite-path
    /// identifier as accepted by `xcresulttool` (e.g.
    /// `"ExampleSUITests/foo()"`), without the module prefix.
    case extractTo(URL, testID: String? = nil)
}

// MARK: - AttachmentLookupKey

/// Lookup key used to join `AttachmentsDTO` entries back to the parser-built
/// `Test` instances. Matches `testIdentifierURL` (from the manifest) against the
/// owning test-case node's `nodeIdentifierURL`, refined by `repetitionNumber`
/// when the test ran with retries.
struct AttachmentLookupKey: Hashable {
    let testIdentifierURL: String
    let repetitionNumber: Int?

    func hash(into hasher: inout Hasher) {
        hasher.combine(testIdentifierURL)
        hasher.combine(repetitionNumber)
    }
}

extension Report {
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
    ///   - includeTests: Whether to parse and include test results (suites/cases).
    ///     Defaults to `true`. Disabling skips the slowest `xcresulttool` call and is
    ///     useful for warnings-only flows; in that case `Module.suites` is empty but
    ///     `files`, `Module.files`, and warnings/errors remain populated.
    ///   - attachments: Whether to extract test attachments to disk and surface them
    ///     on `Test.attachments`. Defaults to `.skip`. Implies `includeTests == true`
    ///     to have anything to attach to; passing `.extractTo(_)` with
    ///     `includeTests: false` is allowed but results in zero attachments.
    /// - Throws: An error if the `.xcresult` file cannot be parsed.
    public init(
        xcresultPath: URL,
        includeCoverage: Bool = true,
        includeWarnings: Bool = true,
        includeTests: Bool = true,
        attachments: AttachmentPolicy = .skip
    ) async throws {
        let testResultsDTO: TestResultsDTO? =
            includeTests ? try await TestResultsDTO(from: xcresultPath) : nil
        let buildResultsDTO: BuildResultsDTO? =
            includeWarnings ? try await BuildResultsDTO(from: xcresultPath) : nil
        let coverageReportDTO: CoverageReportDTO? =
            includeCoverage ? try await CoverageReportDTO(from: xcresultPath) : nil

        let attachmentLookup: [AttachmentLookupKey: [Module.Suite.RepeatableTest.Test.Attachment]]
        if includeTests, case .extractTo(let outputDirectory, let testID) = attachments {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            let dto = try await AttachmentsDTO(
                from: xcresultPath,
                outputDirectory: outputDirectory,
                testID: testID
            )
            attachmentLookup = Self.buildAttachmentLookup(
                dto: dto,
                outputDirectory: outputDirectory
            )
        } else {
            attachmentLookup = [:]
        }

        let (warningsByFileName, errorsByFileName) = await Self
            .parseIssueMaps(from: buildResultsDTO)

        let files = Self.buildFiles(
            coverageReportDTO: coverageReportDTO,
            warningsByFileName: warningsByFileName,
            errorsByFileName: errorsByFileName
        )

        let testNodesByModule = Self.testNodesByCanonicalModule(
            testResultsDTO: testResultsDTO,
            coverageReportDTO: coverageReportDTO,
            attachmentLookup: attachmentLookup
        )

        self.files = files
        modules = Self.buildModules(
            files: files,
            testNodesByModule: testNodesByModule,
            coverageReportDTO: coverageReportDTO
        )
        coverage = Self.computeTotalCoverage(
            includeCoverage: includeCoverage,
            coverageReportDTO: coverageReportDTO,
            files: files
        )
    }

    // MARK: - Attachment lookup

    /// Folds the flat manifest from `xcresulttool export attachments` into a
    /// `(testIdentifierURL, repetitionNumber) → [Attachment]` map. Entries
    /// whose `repetitionNumber` is `nil` participate as the catch-all bucket
    /// for tests that ran without retries.
    static func buildAttachmentLookup(
        dto: AttachmentsDTO,
        outputDirectory: URL
    )
        -> [AttachmentLookupKey: [Module.Suite.RepeatableTest.Test.Attachment]]
    {
        var result = [AttachmentLookupKey: [Module.Suite.RepeatableTest.Test.Attachment]]()
        for entry in dto {
            for raw in entry.attachments {
                let key = AttachmentLookupKey(
                    testIdentifierURL: entry.testIdentifierURL,
                    repetitionNumber: raw.repetitionNumber
                )
                let attachment = Module.Suite.RepeatableTest.Test.Attachment(
                    name: raw.suggestedHumanReadableName,
                    exportedFileName: raw.exportedFileName,
                    path: outputDirectory.appending(path: raw.exportedFileName),
                    contentType: mimeType(forFileName: raw.exportedFileName),
                    isAssociatedWithFailure: raw.isAssociatedWithFailure,
                    repetitionNumber: raw.repetitionNumber,
                    timestamp: raw.timestamp.map { Date(timeIntervalSince1970: $0) },
                    deviceID: raw.deviceID,
                    configurationName: raw.configurationName
                )
                result[key, default: []].append(attachment)
            }
        }
        return result
    }

    /// Infers a MIME type from a filename via `UTType`. Returns `nil` when no
    /// extension or no mapping is available.
    private static func mimeType(forFileName fileName: String) -> String? {
        let ext = (fileName as NSString).pathExtension
        guard ext.isEmpty == false else {
            return nil
        }

        #if canImport(UniformTypeIdentifiers)
        return UTType(filenameExtension: ext)?.preferredMIMEType
        #else
        return nil
        #endif
    }

    // MARK: - Helpers used by init

    private static func parseIssueMaps(
        from buildResultsDTO: BuildResultsDTO?
    ) async
        -> (warnings: [String: [File.Issue]], errors: [String: [File.Issue]])
    {
        guard let buildResultsDTO else {
            return ([:], [:])
        }

        let warnings = await parseWarnings(from: buildResultsDTO)
        let errors = await parseErrors(from: buildResultsDTO)
        return (warnings, errors)
    }

    /// Build bundle test nodes (root-level tests + top-level suite trees) grouped
    /// by their test bundle name; alias test-bundle names to canonical
    /// coverage-target names so they project onto the same Module.
    private static func testNodesByCanonicalModule(
        testResultsDTO: TestResultsDTO?,
        coverageReportDTO: CoverageReportDTO?,
        attachmentLookup: [AttachmentLookupKey: [Module.Suite.RepeatableTest.Test.Attachment]] = [:]
    )
        -> [String: BundleTestNodes]
    {
        let nodesByBundle: [String: BundleTestNodes] =
            testResultsDTO.map { buildSuites(from: $0, attachmentLookup: attachmentLookup) } ?? [:]
        let coverageTargetNames = Set(coverageReportDTO?.targets.map(\.name) ?? [])
        let aliasing = aliasTestBundlesToCoverageTargets(
            testBundleNames: Set(nodesByBundle.keys),
            coverageTargetNames: coverageTargetNames
        )
        var result = [String: BundleTestNodes]()
        for (bundle, nodes) in nodesByBundle {
            let canonical = aliasing[bundle] ?? bundle
            let existing = result[canonical] ?? BundleTestNodes(rootLevelTests: [], suites: [])
            result[canonical] = BundleTestNodes(
                rootLevelTests: existing.rootLevelTests.union(nodes.rootLevelTests),
                suites: existing.suites + nodes.suites
            )
        }
        return result
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
    )
        -> [File]
    {
        var index = FileIndex()
        if let coverageReportDTO {
            index.seed(from: coverageReportDTO)
        }
        index.attach(warningsByFileName, asErrors: false)
        index.attach(errorsByFileName, asErrors: true)
        return index.build()
    }

    /// Mutable working set used while folding coverage + warnings + errors into a single
    /// `[File]` array. Lives next to `buildFiles` because it's an implementation detail.
    private struct FileIndex {
        // MARK: Internal

        mutating func seed(from coverageReportDTO: CoverageReportDTO) {
            for target in coverageReportDTO.targets {
                for fc in target.files {
                    byPath[fc.path] = FileBuilder(
                        name: fc.name,
                        path: fc.path,
                        module: target.name,
                        coverage: File.Coverage(from: fc)
                    )
                    pathsByBasename[fc.name, default: []].append(fc.path)
                    if fc.name.hasSuffix(".swift") {
                        let stem = String(fc.name.dropLast(6))
                        pathsByBasename[stem, default: []].append(fc.path)
                    }
                }
            }
        }

        mutating func attach(_ issues: [String: [File.Issue]], asErrors: Bool) {
            for (basename, list) in issues {
                if let paths = pathsByBasename[basename] {
                    for path in paths {
                        appendToCovered(path: path, list: list, asErrors: asErrors)
                    }
                } else {
                    appendToUncovered(basename: basename, list: list, asErrors: asErrors)
                }
            }
        }

        func build() -> [File] {
            let pathed = byPath.values.map { $0.build() }
            let unpathed = byBasename.values.map { $0.build() }
            return (pathed + unpathed).sorted { lhs, rhs in
                (lhs.path ?? lhs.name) < (rhs.path ?? rhs.name)
            }
        }

        // MARK: Private

        /// path → builder
        private var byPath = [String: FileBuilder]()
        /// basename → set of paths (for issue attribution); a basename can map to several
        /// distinct files (e.g. helper file in two targets).
        private var pathsByBasename = [String: [String]]()
        /// files known only from build issues: keyed by basename (no path).
        private var byBasename = [String: FileBuilder]()

        private mutating func appendToCovered(path: String, list: [File.Issue], asErrors: Bool) {
            if asErrors {
                byPath[path]?.errors.append(contentsOf: list)
            } else {
                byPath[path]?.warnings.append(contentsOf: list)
            }
        }

        private mutating func appendToUncovered(
            basename: String,
            list: [File.Issue],
            asErrors: Bool
        ) {
            if byBasename[basename] == nil {
                byBasename[basename] = FileBuilder(
                    name: basename,
                    path: nil,
                    module: nil,
                    coverage: nil
                )
            }
            if asErrors {
                byBasename[basename]?.errors.append(contentsOf: list)
            } else {
                byBasename[basename]?.warnings.append(contentsOf: list)
            }
        }
    }

    private struct FileBuilder {
        var name: String
        var path: String?
        var module: String?
        var coverage: File.Coverage?
        var warnings = [File.Issue]()
        var errors = [File.Issue]()

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
}
