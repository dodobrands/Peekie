import Foundation

extension Report {
    /// Pre-computes the 1-indexed DFS position of each `Repetition` node under
    /// a test case. Keyed by `TestNode.name`, which Apple guarantees unique
    /// within a single test case (`"First Run"`, `"Retry 1"`, `"Retry 2"`, …
    /// for retry-on-failure; `"Repetition 1"`, `"Repetition 2"`, … for
    /// explicit per-test repeat counts).
    static func repetitionPositionsByName(
        in testCase: TestResultsDTO.TestNode
    )
        -> [String: Int]
    {
        var positions = [String: Int]()
        var counter = 1
        func walk(_ node: TestResultsDTO.TestNode) {
            if node.nodeType == .repetition {
                if positions[node.name] == nil {
                    positions[node.name] = counter
                    counter += 1
                }
                return
            }
            for child in node.children ?? [] {
                walk(child)
            }
        }
        for child in testCase.children ?? [] {
            walk(child)
        }
        return positions
    }
}
