# Build warnings by type — `SPM-26.5-iOS.xcresult`

**Total warnings: 17**

## Breakdown by Xcode `issueType` (raw classification from xcresulttool)

| Count | issueType |
|------:|-----------|
| 8 | Swift Compiler Warning |
| 4 | Swift Compiler Error *(actually warnings — see note below)* |
| 3 | DeprecatedDeclaration |
| 1 | No-usage |
| 1 | ActorIsolatedCall |

> Note: Xcode tags `#warning(...)` directives as `Swift Compiler Error` in the `issueType` field, even though they appear in the `warnings[]` array. So the 4 "Swift Compiler Error" entries here are `#warning` directives, not real errors.

## Breakdown by semantic category (grouped by message pattern)

| Count | Category | Example |
|------:|----------|---------|
| 8 | `#warning(...)` directives | `Some warning from StringUtils` |
| 3 | Deprecated API usage | `'oldFoo()' is deprecated: use newFoo()` |
| 1 | Unused result | `Result of call to 'unusedResultProducer()' is unused` |
| 1 | Optional in string interpolation | `String interpolation produces a debug description for an optional value` |
| 1 | Redundant conditional cast | `Conditional cast from 'Bar' to 'Foo' always succeeds` |
| 1 | Redundant `try` | `No calls to throwing functions occur within 'try' expression` |
| 1 | Unreachable code | `Code after 'return' will never be executed` |
| 1 | Main-actor isolation | `Call to main actor-isolated class method ... in a synchronous nonisolated context` |

## Interpretation

Almost half (8/17) are intentional `#warning(...)` directives developers left in the source — those are TODO markers, not real defects; the remaining 9 are genuine fixes worth prioritizing, with deprecated-API usage (3) being the largest real category.
