import Foundation
import Logging

// MARK: - TestActivitiesDTO

/// Per-test activity tree from `xcrun xcresulttool get test-results activities`.
///
/// Activities are the XCTest/XCUITest step log: `XCTContext.runActivity` titles,
/// attachment markers, and Allure-style metadata activities
/// (`allure.label.<name>:<value>`, `allure.id:<value>`). One `TestRun` per
/// execution of the test, in the same order as `Repetition` nodes of the
/// test-results tree.
struct TestActivitiesDTO: Decodable {
    struct TestRun: Decodable {
        let activities: [Activity]?
    }

    struct Activity: Decodable {
        // MARK: Lifecycle

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
            isAssociatedWithFailure = try container
                .decodeIfPresent(Bool.self, forKey: .isAssociatedWithFailure) ?? false
            childActivities = try container
                .decodeIfPresent([Self].self, forKey: .childActivities)
            attachments = try container
                .decodeIfPresent([ActivityAttachment].self, forKey: .attachments)
        }

        // MARK: Internal

        enum CodingKeys: String, CodingKey {
            case title
            case startTime
            case isAssociatedWithFailure
            case childActivities
            case attachments
        }

        let title: String
        let startTime: Double?
        let isAssociatedWithFailure: Bool
        let childActivities: [Self]?
        let attachments: [ActivityAttachment]?
    }

    /// Attachment reference inside an activity. `uuid` is the prefix of the
    /// `exportedFileName` that `xcresulttool export attachments` writes, which
    /// makes an exact join with the attachment manifest possible.
    struct ActivityAttachment: Decodable {
        let name: String?
        let uuid: String?
    }

    let testRuns: [TestRun]
}

extension TestActivitiesDTO {
    private static let logger = Logger(label: "com.peekie.dto")

    /// Runs `xcrun xcresulttool get test-results activities --test-id <id>` and
    /// decodes the output. One invocation per test — cheap (tens of milliseconds),
    /// but callers iterating thousands of tests should expect the total to add up.
    static func load(xcresultPath: URL, testIdentifier: String) async throws -> Self {
        let data = try await Shell.execute(
            "xcrun",
            arguments: [
                "xcresulttool", "get", "test-results", "activities",
                "--test-id", testIdentifier,
                "--path", xcresultPath.path,
                "--compact",
            ]
        )

        logger.debug(
            "Parsing TestActivitiesDTO",
            metadata: ["testIdentifier": "\(testIdentifier)"]
        )

        return try JSONDecoder().decode(Self.self, from: data)
    }
}
