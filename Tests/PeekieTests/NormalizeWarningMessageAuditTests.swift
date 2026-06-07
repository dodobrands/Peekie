import Foundation
import Testing

@testable import PeekieSDK

/// Audit suite covering #164: how does `normalizeWarningMessage` behave on the
/// multiline shapes xcresult actually emits beyond the well-understood
/// `#warning("…")` directive form?
///
/// These tests document current behavior; they're descriptive ("what does it do
/// today?") rather than prescriptive ("what should it do?"). If we decide a
/// shape needs different handling, change the implementation and these
/// expectations together.
@Suite
struct NormalizeWarningMessageAuditTests {
    /// `#warning("…")` directive — the form the existing regex was tuned for.
    /// Expected: drop the caret-line and the directive echo, keep just the
    /// human-readable message.
    @Test
    func warningDirectiveCollapsesToHumanMessage() {
        let input = """
            Some warning from Calculator
                    #warning("Some warning from Calculator")
                             ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            """
        let out = Report.normalizeWarningMessage(input)
        #expect(out == "Some warning from Calculator")
    }

    /// Single-line `Main actor-isolated …` warning — no-op for normalization.
    @Test
    func singleLineDiagnosticPassesThroughUnchanged() {
        let input =
            "Main actor-isolated initializer 'init()' cannot be called from outside of the actor"
        let out = Report.normalizeWarningMessage(input)
        #expect(out == input)
    }

    /// Multi-paragraph diagnostic with a `note:` block — Swift 6 Sendable
    /// diagnostics tend to have this shape. Documents that the newline between
    /// the primary message and the note is collapsed to a single space.
    @Test
    func sendableLikeNoteBlockGetsCollapsedToOneLine() {
        let input = """
            Capture of 'self' with non-sendable type 'Foo' in a `@Sendable` closure
            note: class 'Foo' does not conform to the 'Sendable' protocol
            """
        let out = Report.normalizeWarningMessage(input)
        #expect(
            out
                == "Capture of 'self' with non-sendable type 'Foo' in a `@Sendable` closure note: class 'Foo' does not conform to the 'Sendable' protocol"
        )
        // The `note:` survives, but its visual separation from the main message is gone.
        // Acceptable for dashboards / single-line logs; if a UI needs the structure,
        // it should read the raw `BuildResultsDTO.Issue.message` instead — #164 left
        // open the option of exposing `rawMessage` as a follow-up.
    }

    /// Wrapped long generic type name — compiler wraps long types across lines
    /// and indents the continuation. Documents that this collapses to a clean
    /// single line, which is the desired outcome.
    @Test
    func wrappedLongTypeNameCollapsesToOneLine() {
        let input = """
            Cannot convert value of type 'Dictionary<String, Array<Dictionary<Int,
                Result<Foo, Bar>>>>' to expected argument type 'Int'
            """
        let out = Report.normalizeWarningMessage(input)
        #expect(
            out
                == "Cannot convert value of type 'Dictionary<String, Array<Dictionary<Int, Result<Foo, Bar>>>>' to expected argument type 'Int'"
        )
    }

    /// Caret line on a non-`#warning` diagnostic (compiler shows `^` under the
    /// offending span). Documents that the caret line is correctly stripped.
    @Test
    func caretLineOnGenericDiagnosticIsStripped() {
        let input = """
            'oldFoo()' is deprecated: use newFoo()
                ^~~~~~~~
            """
        let out = Report.normalizeWarningMessage(input)
        #expect(out == "'oldFoo()' is deprecated: use newFoo()")
    }

    /// Diagnostic that's already only whitespace — defensive case. Should
    /// return empty string so the caller can drop the issue entirely.
    @Test
    func whitespaceOnlyMessageReturnsEmpty() {
        let input = "   \n   \n"
        let out = Report.normalizeWarningMessage(input)
        #expect(out.isEmpty)
    }
}
