import Foundation

infix operator ?!: NilCoalescingPrecedence

/// Throws the right hand side error if the left hand side optional is `nil`.
public func ?! <T>(value: T?, error: @autoclosure () -> Error) throws -> T {
    guard let value else {
        throw error()
    }

    return value
}
