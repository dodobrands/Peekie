# Build warnings by type — `SPM-26.5-iOS.xcresult`

| Count | Type | Notes |
|---:|---|---|
| 8 | `Swift Compiler Warning` | Generic compiler warnings — start here |
| 4 | `Swift Compiler Error` | All 4 are `#warning("...")` developer markers (Xcode mis-tags `#warning` directives as errors). Not real defects — these are intentional TODO markers left in code |
| 3 | `DeprecatedDeclaration` | Usage of APIs marked `@available(*, deprecated)` |
| 1 | `ActorIsolatedCall` | Swift concurrency isolation issue |
| 1 | `No-usage` | Unused declaration |

**Total: 17 warnings across 5 types.**

Interpretation: 13 actionable warnings to prioritize (8 generic Swift warnings + 3 deprecations + 1 concurrency + 1 unused). The 4 `Swift Compiler Error` entries are `#warning(...)` TODO markers developers left in the source — triage them separately as backlog notes, not defects.
