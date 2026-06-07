// swiftlint:disable:next blanket_disable_command
// swiftlint:disable missing_docs
import Foundation

public extension Measurement where UnitType: UnitDuration {
    static func testMake(
        unit: UnitDuration = .milliseconds,
        value: Double = 0
    )
        -> Measurement<UnitDuration>
    {
        .init(value: value, unit: unit)
    }

    static func *(left: Self, right: Int) -> Self {
        .init(value: left.value * Double(right), unit: left.unit)
    }

    static func /(left: Self, right: Int) -> Self {
        .init(value: left.value / Double(right), unit: left.unit)
    }
}
