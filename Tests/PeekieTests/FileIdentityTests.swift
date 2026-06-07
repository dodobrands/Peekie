import Foundation
import Testing
@testable import PeekieSDK

struct FileIdentityTests {
    @Test
    func filesWithSamePathAreEqual() {
        let lhs = Report.File(name: "Foo.swift", path: "/x/Foo.swift", module: "X")
        let rhs = Report.File(name: "Foo.swift", path: "/x/Foo.swift", module: "Y")
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    @Test
    func filesWithSameNameButDifferentPathsAreDistinct() {
        let lhs = Report.File(name: "Foo.swift", path: "/x/Foo.swift", module: "X")
        let rhs = Report.File(name: "Foo.swift", path: "/y/Foo.swift", module: "Y")
        #expect(lhs != rhs)
    }

    @Test
    func filesWithoutPathFallBackToNameForIdentity() {
        let lhs = Report.File(name: "Foo.swift", path: nil)
        let rhs = Report.File(name: "Foo.swift", path: nil)
        #expect(lhs == rhs)
    }
}
