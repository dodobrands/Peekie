import Foundation

extension Array where Element: Equatable {
    var elementsAreEqual: Bool {
        dropFirst().allSatisfy { $0 == first }
    }
}

public extension [Report.Module.Suite] {
    /// Convenience lookup by `name`.
    subscript(_ name: String) -> Element? {
        first { $0.name == name }
    }
}

public extension [Report.File] {
    /// Convenience lookup by `name`.
    subscript(_ name: String) -> Element? {
        first { $0.name == name }
    }
}

public extension [Report.Module] {
    /// Convenience lookup by `name`.
    subscript(_ name: String) -> Element? {
        first { $0.name == name }
    }
}

public extension [Report.Module.Suite.RepeatableTest] {
    /// Sum of the per-test totals; assumes all tests use the same `UnitDuration`.
    var totalDuration: Measurement<UnitDuration> {
        assert(map(\.totalDuration.unit).elementsAreEqual)
        let value = map(\.totalDuration.value).sum()
        let unit =
            first?.totalDuration.unit
                ?? Report.Module.Suite.RepeatableTest.Test.defaultDurationUnit
        return .init(value: value, unit: unit)
    }
}

public extension Report.Module.Suite.RepeatableTest.Test.Status {
    /// Emoji icon representing the test status
    var icon: String {
        switch self {
        case .success:
            "✅"
        case .failure:
            "❌"
        case .skipped:
            "⏭️"
        case .mixed:
            "⚠️"
        case .expectedFailure:
            "🤡"
        case .unknown:
            "🤷"
        }
    }
}
