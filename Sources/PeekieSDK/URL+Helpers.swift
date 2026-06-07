import Foundation

// MARK: - URL.Error

public extension URL {
    enum Error: Swift.Error {
        case noResourceValues
    }
}

public extension URL {
    /// Returns a relative path from a base URL
    /// - Parameter baseURL: The base URL to calculate the relative path from.
    /// - Returns: A relative path if possible, otherwise nil.
    func relativePath(from baseURL: URL) -> String? {
        // Check if both URLs are file URLs and that the base URL is a directory
        guard isFileURL, baseURL.isFileURL, baseURL.hasDirectoryPath else {
            return nil
        }

        // Remove/replace "." and "..", make sure URLs are absolute:
        let pathComponents = standardized.pathComponents
        let basePathComponents = baseURL.standardized.pathComponents

        // Find the number of common path components
        let commonPart = zip(pathComponents, basePathComponents).prefix { $0 == $1 }.count

        // Build the relative path
        let relativeComponents =
            Array(repeating: "..", count: basePathComponents.count - commonPart)
                + pathComponents.dropFirst(commonPart)

        return relativeComponents.joined(separator: "/")
    }
}
