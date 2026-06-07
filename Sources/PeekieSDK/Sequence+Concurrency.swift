import Foundation

public extension Sequence {
    /// Sequential async map: awaits each transform in order.
    func asyncMap<T>(
        _ transform: @escaping (Element) async throws -> T
    ) async rethrows
        -> [T]
    {
        var results = [T]()
        for element in self {
            let value = try await transform(element)
            results.append(value)
        }
        return results
    }

    /// Parallel map using a task group; result order matches input order.
    func concurrentMap<T: Sendable>(
        _ transform: @Sendable @escaping (Element) async throws -> T
    ) async rethrows
        -> [T] where Element: Sendable
    {
        let elements = Array(self)
        return try await withThrowingTaskGroup(of: (Int, T).self) { group in
            for (index, element) in elements.enumerated() {
                group.addTask {
                    try await (index, transform(element))
                }
            }
            var results = [T?](repeating: nil, count: elements.count)
            for try await (index, value) in group {
                results[index] = value
            }
            // All tasks are finished; force unwrap is safe.
            return results.compactMap(\.self)
        }
    }

    /// Parallel compactMap using a task group; keeps input order for kept elements.
    func concurrentCompactMap<T: Sendable>(
        _ transform: @Sendable @escaping (Element) async throws -> T?
    ) async rethrows
        -> [T] where Element: Sendable
    {
        let elements = Array(self)
        return try await withThrowingTaskGroup(of: (Int, T?).self) { group in
            for (index, element) in elements.enumerated() {
                group.addTask {
                    try await (index, transform(element))
                }
            }
            var results = [T?](repeating: nil, count: elements.count)
            for try await (index, value) in group {
                results[index] = value
            }
            return results.compactMap(\.self)
        }
    }

    /// Parallel forEach without caring about order.
    func concurrentForEach(
        _ body: @Sendable @escaping (Element) async throws -> Void
    ) async rethrows where Element: Sendable {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for element in self {
                let item = element
                group.addTask {
                    try await body(item)
                }
            }
            try await group.waitForAll()
        }
    }
}
