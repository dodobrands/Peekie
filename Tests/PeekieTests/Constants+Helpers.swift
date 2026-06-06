import Foundation
import Testing

struct Constants {
    private static var resourcesPath: URL {
        get throws {
            guard let resourceURL = Bundle.module.resourceURL else {
                throw TestError.couldNotFindBundleResourceURL
            }
            // When using .copy("Resources"), the Resources folder contents are copied to resourceURL
            // Check if Resources subdirectory exists, otherwise use resourceURL directly
            let resourcesSubdir = resourceURL.appendingPathComponent("Resources")
            if FileManager.default.fileExists(atPath: resourcesSubdir.path) {
                return resourcesSubdir
            }
            // If Resources subdirectory doesn't exist, xcresult files are directly in resourceURL
            return resourceURL
        }
    }

    private static var testsReportPaths: [URL] {
        get throws {
            let resourcesURL = try resourcesPath
            let fileManager = FileManager.default

            guard fileManager.fileExists(atPath: resourcesURL.path) else {
                throw TestError.resourcesDirectoryDoesNotExist(path: resourcesURL.path)
            }

            guard
                let contents = try? fileManager.contentsOfDirectory(
                    at: resourcesURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            else {
                throw TestError.couldNotReadResourcesDirectory
            }

            return contents.filter { url in
                url.pathExtension == "xcresult"
                    && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
    }

    /// Returns array of xcresult file names for use in parameterized tests
    /// Returns empty array if paths cannot be loaded (test will be skipped)
    static var testsReportFileNames: [String] {
        ((try? testsReportPaths) ?? []).map { $0.lastPathComponent }
    }

    /// Copies xcresult bundle to a temporary directory to avoid SQLite access conflicts
    /// when multiple tests access the same xcresult file concurrently.
    ///
    /// Problem: xcresult bundles contain SQLite databases internally. When multiple tests
    /// run in parallel and access the same xcresult file via `xcrun xcresulttool` and
    /// `xcrun xccov`, they all read from the same SQLite database, which causes errors like:
    ///
    /// ```
    /// processFailed(exitCode: exited(64), error: "Error: "database.sqlite3" couldn't be moved
    /// to "Peekie-15.0.xcresult" because an item with the same name already exists.")
    /// ```
    ///
    /// Note: This issue appears to be specific to Xcode 15.0 xcresult files. The exact reason
    /// is unknown, but it's likely related to how SQLite database files are structured or
    /// accessed in Xcode 15.0's xcresult format. Newer versions (e.g., 26.5) don't exhibit
    /// this behavior, but we apply the fix to all xcresult files for consistency and safety.
    ///
    /// This happens because SQLite tries to move/access database files concurrently, leading to:
    /// - Database file access conflicts
    /// - Race conditions
    /// - Flaky test failures in CI environments
    ///
    /// Solution: Each test gets its own copy of the xcresult bundle in a temporary directory,
    /// ensuring complete isolation and preventing concurrent SQLite access conflicts.
    ///
    /// - Parameter xcresultPath: The original xcresult bundle path
    /// - Returns: URL to the temporary copy
    /// - Throws: An error if copying fails
    static func copyXcresultToTemporaryDirectory(_ xcresultPath: URL) throws -> URL {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let uniqueName = UUID().uuidString + ".xcresult"
        let tempXcresultPath = tempDir.appendingPathComponent(uniqueName)

        // Remove destination if it exists (shouldn't happen with UUID, but just in case)
        if fileManager.fileExists(atPath: tempXcresultPath.path) {
            try fileManager.removeItem(at: tempXcresultPath)
        }

        // Copy the entire bundle (directory) recursively
        try fileManager.copyItem(at: xcresultPath, to: tempXcresultPath)

        return tempXcresultPath
    }

    /// Returns URL for a given xcresult file name
    static func url(for fileName: String) throws -> URL {
        let paths = try testsReportPaths
        guard let url = paths.first(where: { $0.lastPathComponent == fileName }) else {
            throw TestError.couldNotFindXcresultFile(fileName: fileName)
        }
        return url
    }
}

enum TestError: Error {
    case couldNotFindBundleResourceURL
    case resourcesDirectoryDoesNotExist(path: String)
    case couldNotReadResourcesDirectory
    case couldNotFindXcresultFile(fileName: String)
}
