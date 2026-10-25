import Foundation
import Testing
@testable import PeekieSDK

struct UnassociatedIssuesTests {
    // MARK: Internal

    struct CLIResult {
        let code: Int32
        let output: String
        let error: String
    }

    @Test
    func mixedManifestKeepsDiagnosticsOutsideRealTests() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dto = try JSONDecoder().decode(
            AttachmentsDTO.self,
            from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        )
        let lookup = Report.buildAttachmentLookup(dto: dto, outputDirectory: directory)
        let results = try JSONDecoder().decode(
            TestResultsDTO.self,
            from: Data(contentsOf: directory.appendingPathComponent("tests.json"))
        )
        let bundles = Report.buildSuites(from: results, attachmentLookup: lookup.tests)
        let tests = try #require(bundles["ExampleTests"]?.rootLevelTests)
        let test = try #require(tests.first?.tests.first)
        #expect(lookup.tests.count == 1)
        #expect(tests.count == 1 && test.status == .success)
        #expect(test.attachments.map(\.exportedFileName) == ["normal.txt"])
        #expect(lookup.unassociated.count == 8)
        let report = Report(
            files: [], modules: [.init(name: "ExampleTests")], coverage: nil,
            rootLevelTestsByModule: ["ExampleTests": tests],
            unassociatedAttachments: lookup.unassociated
        )
        let rows = try JSONSerialization.jsonObject(
            with: Data(AttachmentsFormatter().json(report, include: [.failure]).utf8)
        ) as? [[String: Any]]
        #expect(rows?.count == 8)
        #expect(rows?.allSatisfy { $0["scope"] as? String == "report" } == true)
        let listing = AttachmentsFormatter().list(report, include: [.failure])
        #expect(listing.contains("Issues recorded without an associated test or suite"))
        for attachment in lookup.unassociated {
            #expect(listing.contains(attachment.exportedFileName))
        }
        for grouping in [JSONFormatter.Grouping.bySuite, .fullyQualified] {
            let json = try JSONSerialization.jsonObject(
                with: Data(JSONFormatter().format(report, grouping: grouping).utf8)
            ) as? [String: Any]
            #expect((json?["unassociatedAttachments"] as? [Any])?.count == 8)
        }
        let output = directory.appendingPathComponent("allure")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try "existing=value".write(
            to: output.appendingPathComponent("environment.properties"),
            atomically: true,
            encoding: .utf8
        )
        let summary = try AllureFormatter().write(report: report, to: output)
        #expect(summary.resultsTotal == 1 && summary.resultCountsByStatus == ["passed": 1])
        #expect(summary.attachmentsTotal == 9)
        // All eight payloads are literal, byte-identical exports; keep one source fixture.
        let original = try Data(contentsOf: directory.appendingPathComponent("diagnostic.txt"))
        for attachment in lookup.unassociated {
            try FileManager.default.removeItem(at: attachment.path)
            let saved = output
                .appendingPathComponent("unassociated-issues/" + attachment.exportedFileName)
            #expect(try Data(contentsOf: saved) == original)
        }
        let environment = try String(
            contentsOf: output.appendingPathComponent("environment.properties"),
            encoding: .utf8
        )
        #expect(environment.hasPrefix("existing=value\n"))
        #expect(environment.contains("ERROR: 8 diagnostic attachments"))
        #expect(environment.contains("DependencyValues.DateGeneratorKey"))
    }

    @Test(arguments: [
        #"{"attachments":[]}"#,
        #"{"testIdentifier":"Unknown bucket","attachments":[]}"#,
        #"{"testIdentifierURL":"","attachments":[]}"#,
    ])
    func unknownURLLessRecordStillFails(_ json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AttachmentsDTO.self, from: Data("[\(json)]".utf8))
        }
    }

    @Test(arguments: ["allure", "json", "attachments"])
    func cliSavesDiagnosticsBeforeFailing(_ format: String) throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("output")
        let arguments = format == "attachments"
            ? ["attachments", "unused.xcresult", "--output-dir", output.path]
            : ["tests", "unused.xcresult", "--format", format]
            + (format == "allure" ? ["--output-dir", output.path]
                : ["--attachments", "export", "--attachments-to", output.path])
        let result = try runCLI(arguments, fixture: directory)
        #expect(result.code != 0)
        #expect(result.error.contains("8 diagnostic attachments (not a test count)"))
        let saved = format == "allure" ? output
            .appendingPathComponent("unassociated-issues") : output
        let dto = try JSONDecoder().decode(
            AttachmentsDTO.self,
            from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        )
        for attachment in dto[0].attachments {
            #expect(try Data(contentsOf: saved.appendingPathComponent(attachment.exportedFileName))
                == Data(contentsOf: directory.appendingPathComponent("diagnostic.txt")))
        }
        if format == "allure" {
            #expect(result.output.contains("Exported 1 Allure results (passed: 1), 9 attachments"))
            let extraction = try String(
                contentsOf: directory.appendingPathComponent("export-path.txt"),
                encoding: .utf8
            )
            #expect(FileManager.default.fileExists(atPath: extraction) == false)
        }
    }

    @Test(arguments: [false, true])
    func cliDoesNotFailWithoutGlobalFailures(_ warningOnly: Bool) throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = directory.appendingPathComponent("manifest.json")
        let text = try String(contentsOf: manifest, encoding: .utf8)
        let data = warningOnly ? Data(text.replacing("true", with: "false").utf8)
            : try JSONSerialization.data(withJSONObject: Array(
                (JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any] ?? []).dropFirst()
            ))
        try data.write(to: manifest)
        let result = try runCLI(
            [
                "tests",
                "unused.xcresult",
                "--format",
                "allure",
                "--output-dir",
                directory.appendingPathComponent("output").path,
            ],
            fixture: directory
        )
        #expect(result.code == 0, "CLI stderr: \(result.error)")
        #expect(result.error.contains("Warning:") == warningOnly)
    }

    // MARK: Private

    private func fixtureDirectory() throws -> URL {
        let source = try #require(Bundle.module.resourceURL)
            .appendingPathComponent("Resources/UnassociatedIssues")
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: directory)
        let dto = try JSONDecoder().decode(
            AttachmentsDTO.self,
            from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        )
        for attachment in dto[0].attachments {
            try FileManager.default.copyItem(
                at: directory.appendingPathComponent("diagnostic.txt"),
                to: directory
                    .appendingPathComponent(attachment.exportedFileName)
            )
        }
        return directory
    }

    private func runCLI(_ arguments: [String], fixture: URL) throws
        -> CLIResult
    {
        let stub = fixture.appendingPathComponent("xcrun")
        try """
        #!/bin/sh
        if [ "$2" = get ]; then
          cat "$PEEKIE_FIXTURE/tests.json"
        else
          while [ "$1" != --output-path ]; do shift; done
          shift
          printf %s "$1" > "$PEEKIE_FIXTURE/export-path.txt"
          cp "$PEEKIE_FIXTURE/manifest.json" "$PEEKIE_FIXTURE/"*.txt "$1/"
        fi
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        let process = Process()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        process.executableURL = root.appendingPathComponent(".build/debug/peekie")
        process.arguments = arguments
        // Subprocess 0.2 searches PATH as a Set; a local executable takes precedence reliably.
        process.currentDirectoryURL = fixture
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = fixture.path + ":/usr/bin:/bin"
        environment["PEEKIE_FIXTURE"] = fixture.path
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        return CLIResult(
            code: process.terminationStatus,
            output: String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ),
            error: String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}
