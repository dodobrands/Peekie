import Foundation

struct BuildResultsDTO: Decodable, Sendable {
    let warnings: [Issue]

    struct Issue: Decodable, Sendable {
        let issueType: String
        let message: String
        let sourceURL: String?
    }
}

extension BuildResultsDTO.Issue {
    var fileName: String? {
        guard let sourceURL else { return nil }
        let url = URL(string: sourceURL) ?? URL(fileURLWithPath: sourceURL)
        let fragmentTrimmed = URL(
            string: url.absoluteString.components(separatedBy: "#").first ?? url.absoluteString)
        return (fragmentTrimmed ?? url).lastPathComponent
    }

    /// Parses Apple's `sourceURL` fragment (`...#StartingLineNumber=N&...`) into a typed location.
    /// Returns `nil` when `sourceURL` is absent, has no fragment, or the fragment carries no
    /// `StartingLineNumber` key — line is the minimum we need to surface a location at all.
    var location: Report.Module.File.Issue.Location? {
        guard let sourceURL else { return nil }
        guard
            let fragment = sourceURL.split(separator: "#", maxSplits: 1).dropFirst().first
        else { return nil }

        let params: [String: String] =
            fragment
            .split(separator: "&")
            .reduce(into: [:]) { acc, part in
                let kv = part.split(separator: "=", maxSplits: 1)
                guard kv.count == 2 else { return }
                acc[String(kv[0])] = String(kv[1])
            }

        guard let startLine = params["StartingLineNumber"].flatMap(Int.init) else { return nil }

        return .init(
            startLine: startLine,
            startColumn: params["StartingColumnNumber"].flatMap(Int.init),
            endLine: params["EndingLineNumber"].flatMap(Int.init),
            endColumn: params["EndingColumnNumber"].flatMap(Int.init)
        )
    }
}
