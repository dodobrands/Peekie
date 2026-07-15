import Foundation

// MARK: - Steps Support

extension AllureFormatter {
    /// Allure metadata extracted from specially-titled activities, the
    /// convention established by eroshenkoam/xcresults:
    /// `allure.id:`, `allure.name:`, `allure.description:`,
    /// `allure.label.<name>:<value>`.
    struct ActivityMetadata {
        // MARK: Internal

        var labels = [AllureTestResult.Label]()
        var nameOverride: String?
        var description: String?

        /// Consumes the title when it is a metadata activity.
        mutating func consume(title: String) -> Bool {
            if let value = value(of: "allure.id:", in: title) {
                labels.append(.init(name: "AS_ID", value: value))
                return true
            }
            if let value = value(of: "allure.name:", in: title) {
                nameOverride = value
                return true
            }
            if let value = value(of: "allure.description:", in: title) {
                description = value
                return true
            }
            if title.hasPrefix("allure.label.") {
                let payload = title.dropFirst("allure.label.".count)
                guard let colon = payload.firstIndex(of: ":") else {
                    return true
                }

                labels.append(.init(
                    name: String(payload[..<colon]),
                    value: String(payload[payload.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                ))
                return true
            }
            return false
        }

        // MARK: Private

        private func value(of prefix: String, in title: String) -> String? {
            guard title.hasPrefix(prefix) else {
                return nil
            }

            return String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
    }

    /// Maps one execution's activity tree to Allure steps, collecting metadata
    /// labels, result-level attachments and consuming exported attachment files
    /// referenced by activities.
    struct StepsBuilder {
        // MARK: Lifecycle

        init(
            testAttachments: [Report.Module.Suite.RepeatableTest.Test.Attachment],
            makeUUID: @escaping () -> UUID
        ) {
            self.makeUUID = makeUUID
            attachmentsByUUIDPrefix = .init(
                testAttachments.map { attachment in
                    ((attachment.exportedFileName as NSString).deletingPathExtension, attachment)
                }
            ) { first, _ in first }
        }

        // MARK: Internal

        var metadata = ActivityMetadata()
        var resultAttachments = [AllureTestResult.Attachment]()

        /// Attachments not referenced from any activity — they stay on the
        /// result itself so nothing exported is lost.
        var unclaimedAttachments: [AllureTestResult.Attachment] {
            attachmentsByUUIDPrefix.values.map { makeAllureAttachment(from: $0) }
        }

        /// Builds steps from activities. Metadata activities are consumed into
        /// `metadata` at any depth; the synthetic "Start Test at …" activity is
        /// not a step, but its attachments (e.g. screen recordings) surface on
        /// the result.
        mutating func makeSteps(
            _ activities: [TestActivitiesDTO.Activity],
            runStopMs: Int
        )
            -> [AllureTestResult.Step]
        {
            var steps = [AllureTestResult.Step]()

            for (index, activity) in activities.enumerated() {
                if metadata.consume(title: activity.title) {
                    continue
                }

                let attachments = claimAttachments(of: activity)

                if activity.title.hasPrefix("Start Test at") {
                    resultAttachments.append(contentsOf: attachments)
                    continue
                }

                let startMs = activity.startTime.map { Int(($0 * 1000).rounded()) } ?? runStopMs
                let nextStartMs = activities.dropFirst(index + 1)
                    .compactMap(\.startTime)
                    .first
                    .map { Int(($0 * 1000).rounded()) }
                let stopMs = min(max(nextStartMs ?? runStopMs, startMs), runStopMs)

                let childSteps = makeSteps(
                    activity.childActivities ?? [],
                    runStopMs: stopMs
                )

                steps.append(
                    AllureTestResult.Step(
                        name: activity.title,
                        status: activity.isAssociatedWithFailure ? "failed" : "passed",
                        stage: "finished",
                        start: startMs,
                        stop: stopMs,
                        steps: childSteps,
                        attachments: attachments
                    )
                )
            }

            return steps
        }

        // MARK: Private

        private var attachmentsByUUIDPrefix: [
            String: Report.Module.Suite.RepeatableTest.Test.Attachment
        ]

        private let makeUUID: () -> UUID

        private mutating func claimAttachments(
            of activity: TestActivitiesDTO.Activity
        )
            -> [AllureTestResult.Attachment]
        {
            (activity.attachments ?? []).compactMap { reference in
                guard let uuid = reference.uuid,
                      let attachment = attachmentsByUUIDPrefix.removeValue(forKey: uuid)
                else {
                    return nil
                }

                return makeAllureAttachment(from: attachment, nameOverride: reference.name)
            }
        }

        private func makeAllureAttachment(
            from attachment: Report.Module.Suite.RepeatableTest.Test.Attachment,
            nameOverride: String? = nil
        )
            -> AllureTestResult.Attachment
        {
            let fileExtension = (attachment.exportedFileName as NSString).pathExtension
            let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
            return AllureTestResult.Attachment(
                name: nameOverride ?? attachment.name,
                source: "\(makeUUID().uuidString.lowercased())-attachment\(suffix)",
                type: attachment.contentType,
                originalPath: attachment.path
            )
        }
    }

    /// Loads activity trees for every test of the report that carries a
    /// canonical identifier. Tests whose activities cannot be read still get
    /// plain results — steps are an enrichment, not a requirement.
    func loadActivities(
        report: Report,
        xcresultPath: URL
    ) async
        -> [String: TestActivitiesDTO]
    {
        var identifiers = [String]()
        for module in report.modules {
            let suites = report.suites(in: module).flatMap { Self.flatten($0) }
            for suite in suites {
                identifiers.append(contentsOf: suite.repeatableTests.compactMap(\.nodeIdentifier))
            }
            identifiers.append(
                contentsOf: report.rootLevelTests(in: module).compactMap(\.nodeIdentifier)
            )
        }

        var result = [String: TestActivitiesDTO]()
        for identifier in identifiers {
            guard let dto = try? await TestActivitiesDTO.load(
                xcresultPath: xcresultPath,
                testIdentifier: identifier
            ) else {
                continue
            }

            result[identifier] = dto
        }
        return result
    }
}
