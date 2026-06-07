import Foundation
import Testing
@testable import PeekieSDK

struct FileIdentityTests {
    @Test
    func filesWithSamePathAreEqual() {
        let a = Report.File(name: "Foo.swift", path: "/x/Foo.swift", module: "X")
        let b = Report.File(name: "Foo.swift", path: "/x/Foo.swift", module: "Y")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test
    func filesWithSameNameButDifferentPathsAreDistinct() {
        let a = Report.File(name: "Foo.swift", path: "/x/Foo.swift", module: "X")
        let b = Report.File(name: "Foo.swift", path: "/y/Foo.swift", module: "Y")
        #expect(a != b)
    }

    @Test
    func filesWithoutPathFallBackToNameForIdentity() {
        let a = Report.File(name: "Foo.swift", path: nil)
        let b = Report.File(name: "Foo.swift", path: nil)
        #expect(a == b)
    }
}
