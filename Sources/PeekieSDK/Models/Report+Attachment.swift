import Foundation

// MARK: - Report.Module.Suite.RepeatableTest.Test + CustomReflectable

extension Report.Module.Suite.RepeatableTest.Test: CustomReflectable {
    /// Omits `attachments` from `Mirror`-based dumps (e.g. `swift-snapshot-testing`'s
    /// `.dump` strategy) when the array is empty. Keeps snapshots that were recorded
    /// before the attachments field existed byte-for-byte stable so adding the field
    /// is non-breaking for downstream consumers that snapshot `Report`.
    public var customMirror: Mirror {
        var children: [Mirror.Child] = [
            ("duration", duration),
            ("failureMessage", failureMessage as Any),
            ("name", name),
            ("path", path),
            ("skipMessage", skipMessage as Any),
            ("status", status),
        ]
        if attachments.isEmpty == false {
            children.insert(("attachments", attachments), at: 0)
        }
        return Mirror(self, children: children, displayStyle: .struct)
    }
}

// MARK: - Report.Module.Suite.RepeatableTest.Test.Attachment

public extension Report.Module.Suite.RepeatableTest.Test {
    /// An attachment captured during a test execution.
    ///
    /// Mirrors the entries emitted by `xcrun xcresulttool export attachments` in the
    /// generated `manifest.json`. The on-disk file lives at `path`; the original
    /// human-facing name (e.g. `"Sum result"`) is in `name`, while
    /// `exportedFileName` is the UUID-suffixed filename xcresulttool produced.
    struct Attachment: Sendable, Hashable {
        // MARK: Lifecycle

        public init(
            name: String,
            exportedFileName: String,
            path: URL,
            contentType: String? = nil,
            isAssociatedWithFailure: Bool = false,
            repetitionNumber: Int? = nil,
            timestamp: Date? = nil,
            deviceID: String? = nil,
            configurationName: String? = nil
        ) {
            self.name = name
            self.exportedFileName = exportedFileName
            self.path = path
            self.contentType = contentType
            self.isAssociatedWithFailure = isAssociatedWithFailure
            self.repetitionNumber = repetitionNumber
            self.timestamp = timestamp
            self.deviceID = deviceID
            self.configurationName = configurationName
        }

        // MARK: Public

        /// Human-readable name as set in code (e.g. `XCTAttachment(string:).name`,
        /// `Attachment("foo", …)`). Sourced from `suggestedHumanReadableName`.
        public let name: String

        /// Filename xcresulttool wrote into the output directory. Carries a UUID
        /// suffix to keep multiple attachments with the same logical name distinct.
        public let exportedFileName: String

        /// Absolute path to the exported file on disk
        /// (`outputDirectory.appending(path: exportedFileName)`).
        public let path: URL

        /// MIME type inferred from the file extension via `UTType`. `nil` when the
        /// exported file has no extension or no MIME mapping exists.
        public let contentType: String?

        /// `true` when xcresult linked this attachment to a failure on the same test.
        public let isAssociatedWithFailure: Bool

        /// 1-based repetition number for retried tests; `nil` when not reported.
        public let repetitionNumber: Int?

        /// Wall-clock capture time, if xcresult reported one.
        public let timestamp: Date?

        /// Simulator / device identifier on which the test ran.
        public let deviceID: String?

        /// Test plan configuration name (e.g. `"Test Scheme Action"`).
        public let configurationName: String?
    }
}
