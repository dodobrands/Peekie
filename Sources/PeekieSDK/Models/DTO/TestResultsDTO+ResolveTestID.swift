import Foundation

extension TestResultsDTO {
    /// Translates a caller-supplied test reference into the identifier
    /// `xcresulttool` accepts.
    ///
    /// `xcresulttool export attachments --test-id` matches only a node's
    /// `nodeIdentifier` (e.g. ``Suite/`display name`(args:)``) or its
    /// identifier URL. Everything peekie itself prints — qualified names
    /// composed from display names, with an optional ` [arguments]` suffix
    /// for parameterized cases — is rejected. Resolving here lets
    /// `peekie tests` output round-trip into `peekie attachments --test-id`.
    ///
    /// Unrecognized references are returned unchanged so identifier URLs and
    /// ids of nodes peekie did not parse keep working exactly as before.
    func resolveTestID(_ requested: String) -> String {
        let index = Self.identifierIndex(for: testNodes)
        if let match = Self.lookup(requested, in: index) {
            return match
        }
        // `peekie tests` joins qualified-name segments with " / ".
        let slashJoined = requested.replacing(" / ", with: "/")
        if slashJoined != requested, let match = Self.lookup(slashJoined, in: index) {
            return match
        }
        return requested
    }

    // MARK: Private

    private static func lookup(
        _ requested: String,
        in index: [String: String]
    )
        -> String?
    {
        if let match = index[requested] {
            return match
        }
        // Parameterized cases carry a ` [arguments]` display suffix that no
        // xcresult node owns — match the underlying test case instead. Only
        // reached when the verbatim lookup missed, so display names that
        // genuinely end with a bracket still win.
        if requested.hasSuffix("]"),
           let bracket = requested.range(of: " [", options: .backwards)
        {
            return index[String(requested[..<bracket.lowerBound])]
        }
        return nil
    }

    /// Maps every display-path spelling of a test case to its
    /// `nodeIdentifier`: `Suite/Sub/Name` and `Bundle/Suite/Sub/Name` —
    /// consumers commonly strip the module segment before building an id.
    /// First registration wins so duplicate display names stay deterministic.
    private static func identifierIndex(for nodes: [TestNode]) -> [String: String] {
        var index = [String: String]()

        func register(_ key: String, _ identifier: String) {
            guard index[key] == nil else {
                return
            }

            index[key] = identifier
        }

        func visit(_ node: TestNode, suitePath: [String], bundle: String?) {
            switch node.nodeType {
            case .testPlan:
                node.children?.forEach {
                    visit($0, suitePath: [], bundle: nil)
                }

            case .unitTestBundle, .uiTestBundle:
                node.children?.forEach {
                    visit($0, suitePath: [], bundle: node.name)
                }

            case .testSuite:
                node.children?.forEach {
                    visit($0, suitePath: suitePath + [node.name], bundle: bundle)
                }

            case .testCase:
                guard let identifier = node.nodeIdentifier else {
                    return
                }

                let core = (suitePath + [node.name]).joined(separator: "/")
                register(core, identifier)
                if let bundle {
                    register("\(bundle)/\(core)", identifier)
                }

            default:
                break
            }
        }

        for node in nodes {
            visit(node, suitePath: [], bundle: nil)
        }
        return index
    }
}
