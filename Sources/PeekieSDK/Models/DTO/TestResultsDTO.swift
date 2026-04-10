import Foundation

struct TestResultsDTO: Decodable {
    let testNodes: [TestNode]
}

extension TestResultsDTO {
    struct TestNode: Decodable {
        let children: [TestNode]?
        let durationInSeconds: Double?
        let name: String
        let nodeIdentifier: String?
        let nodeIdentifierURL: String?
        let nodeType: NodeType
        let result: Result?
    }

    /// Extracts all test paths from test case children
    /// Returns an array of paths, where each path represents a route through the tree to a Repetition or Arguments node
    /// - Parameter children: Array of child nodes from a test case
    /// - Returns: Array of paths (arrays of PathNode) representing all paths through the tree
    static func extractPaths(from children: [TestNode]) -> [[Report.Module.Suite.RepeatableTest
        .PathNode]]
    {
        var result: [[Report.Module.Suite.RepeatableTest.PathNode]] = []

        func processNode(
            _ node: TestNode,
            path: [Report.Module.Suite.RepeatableTest.PathNode]
        ) {
            // Check if this node should be added to path
            let pathNode: Report.Module.Suite.RepeatableTest.PathNode?
            switch node.nodeType {
            case .device, .arguments, .repetition:
                pathNode = Report.Module.Suite.RepeatableTest.PathNode(
                    name: node.name,
                    type: .init(from: node.nodeType)
                )
            default:
                pathNode = nil
            }

            var newPath = path
            if let pathNode = pathNode {
                newPath.append(pathNode)
            }

            // If this is a repetition node, add to result and stop recursion
            if node.nodeType == .repetition {
                result.append(newPath)
                return
            }

            guard let nodeChildren = node.children else {
                // Leaf node - add to result if it's an arguments node without children
                if node.nodeType == .arguments {
                    result.append(newPath)
                }
                return
            }

            // If this is an arguments node, check if it has repetitions
            if node.nodeType == .arguments {
                let hasRepetitions = nodeChildren.contains { $0.nodeType == .repetition }
                if !hasRepetitions {
                    // Arguments without repetitions - add to result and stop recursion
                    result.append(newPath)
                    return
                }
                // Arguments with repetitions - continue recursion to process repetitions
            }

            // Recursively process children
            for child in nodeChildren {
                // Skip metadata nodes
                guard !child.isMetadata else { continue }
                processNode(child, path: newPath)
            }
        }

        // Process all children
        for child in children {
            // Skip metadata nodes
            guard !child.isMetadata else { continue }
            processNode(child, path: [])
        }

        return result
    }
}

extension TestResultsDTO.TestNode {
    enum NodeType: Decodable, Equatable {
        case testCase
        case testSuite
        case unitTestBundle
        case repetition
        case failureMessage
        case testPlan
        case arguments
        case device
        case runtimeWarning
        case unknown(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            switch rawValue {
            case "Test Case":
                self = .testCase
            case "Test Suite":
                self = .testSuite
            case "Unit test bundle":
                self = .unitTestBundle
            case "Repetition":
                self = .repetition
            case "Failure Message":
                self = .failureMessage
            case "Test Plan":
                self = .testPlan
            case "Arguments":
                self = .arguments
            case "Device":
                self = .device
            case "Runtime Warning":
                self = .runtimeWarning
            default:
                self = .unknown(rawValue)
            }
        }

        static func == (lhs: NodeType, rhs: NodeType) -> Bool {
            switch (lhs, rhs) {
            case (.testCase, .testCase),
                (.testSuite, .testSuite),
                (.unitTestBundle, .unitTestBundle),
                (.repetition, .repetition),
                (.failureMessage, .failureMessage),
                (.testPlan, .testPlan),
                (.arguments, .arguments),
                (.device, .device),
                (.runtimeWarning, .runtimeWarning):
                return true
            case (.unknown(let lhsValue), .unknown(let rhsValue)):
                return lhsValue == rhsValue
            default:
                return false
            }
        }
    }

    enum Result: String, Decodable {
        case passed = "Passed"
        case failed = "Failed"
        case skipped = "Skipped"
        case expectedFailure = "Expected Failure"
    }

    /// Extracts failure message from children nodes
    /// Extracts message after "failed -" separator (e.g., "File.swift:51: failed - Failure message" -> "Failure message")
    /// For Swift Testing format, extracts message after "Issue recorded: " (e.g., "File.swift:56: Issue recorded: Failure message" -> "Failure message")
    var failureMessage: String? {
        guard let children = children,
            let messageNode = children.first(where: { $0.nodeType == .failureMessage })
        else { return nil }
        let message = messageNode.name
        // Try Swift Testing format first: "Issue recorded: "
        if let range = message.range(of: "Issue recorded: ") {
            return String(message[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        // Fallback to XCTest format: "failed -"
        if let range = message.range(of: "failed -") {
            return String(message[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return message
    }

    /// Extracts skip message from children nodes
    /// Extracts message after "skipped -" separator (e.g., "Test skipped - Skip message" -> "Skip message")
    var skipMessage: String? {
        guard let children = children else { return nil }
        let messageNode = children.first {
            $0.nodeType == .failureMessage && $0.name.lowercased().contains("skip")
        }
        guard let message = messageNode?.name else { return nil }
        if let range = message.range(of: "skipped -") {
            return String(message[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return message
    }

    /// Returns true if this node is a metadata node (failureMessage, runtimeWarning)
    var isMetadata: Bool {
        nodeType == .failureMessage || nodeType == .runtimeWarning
    }
}
