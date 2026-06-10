# Migration Guide: 4.x → 5.0

Peekie 5.0 reshapes both the CLI and the SDK. This guide walks every break in dependency order, with before / after snippets. Each section links to the PR that introduced it.

If you only use the CLI, jump to [CLI](#cli). If you embed `PeekieSDK`, read the [SDK](#sdk) section too.

---

## CLI

5.0 restructures the CLI around **data type** subcommands with a `--format` flag. The format-axis commands (`list` / `json` / `sonar`) are gone. Each subcommand only runs the `xcrun` calls it needs — `peekie warnings` no longer pays for test parsing or coverage. ([#179](https://github.com/dodobrands/Peekie/pull/179))

### Subcommand renames

| 4.x | 5.0 |
|---|---|
| `peekie list <xcresult>` | `peekie tests <xcresult>` |
| `peekie list <xcresult> --include failure` | `peekie tests <xcresult> --include failure` |
| `peekie json <xcresult>` | `peekie tests <xcresult> --format json` |
| `peekie json <xcresult> --include-coverage false` | `peekie tests <xcresult> --format json` (coverage isn't fetched) |
| `peekie sonar <xcresult> --tests-path X` | `peekie tests <xcresult> --format sonar --tests-path X` |

### New subcommands

- `peekie warnings <xcresult>` — flat JSON array of `{file, line, column, type, message}`.
- `peekie errors <xcresult>` — same shape as `warnings`, but for the `errors[]` array.
- `peekie coverage <xcresult>` — coverage-only output.

### Removed flags

`--include-coverage` / `--include-warnings` / `--include-tests` no longer exist as CLI flags — the subcommand determines what gets fetched. (The SDK still has them; see below.)

---

## SDK

### Model: `Report` is reshaped around `File` ([#176](https://github.com/dodobrands/Peekie/pull/176))

`Report.files` is now the primary index. `Report.modules` is a projection over it.

| 4.x | 5.0 |
|---|---|
| `Report.modules: Set<Module>` | `Report.modules: [Module]` (projection — not every file appears here) |
| _no analog_ | `Report.files: [File]` (source of truth) |
| `Module.files: Set<File>` | `Module.files: [File]` (subset where `File.module == module.name`) |
| _no analog_ | `File.path: String?` (full path when available) |
| _no analog_ | `File.module: String?` (target name; `nil` for test-less / project-level files) |

Files in test-less targets and files known only from build issues (with no `producingTarget` in xcresult) used to be silently dropped. They now appear in `Report.files` with `module == nil` and their warnings/errors are preserved.

### Type renames ([#176](https://github.com/dodobrands/Peekie/pull/176))

| 4.x | 5.0 |
|---|---|
| `Report.Module.File` | `Report.File` |
| `Report.Module.File.Issue` | `Report.File.Issue` |
| `Report.Module.File.Issue.IssueType` | `Report.File.Issue.IssueType` |
| `Report.Module.File.Issue.Location` | `Report.File.Issue.Location` |
| `Report.Module.File.Coverage` | `Report.File.Coverage` |

### `IssueType` is now an open enum ([#172](https://github.com/dodobrands/Peekie/pull/172))

```swift
// 4.x
public enum IssueType: String, Equatable, Sendable {
    case buildWarning = "Swift Compiler Warning"
}

// 5.0
public enum IssueType: Equatable, Sendable {
    case swiftCompilerWarning
    case swiftCompilerError
    case deprecatedDeclaration
    case noUsage
    case unknown(String)
}
```

- `IssueType.buildWarning` → `.swiftCompilerWarning`.
- `IssueType(rawValue:)` is **no longer Optional** — unrecognized strings return `.unknown(raw)`.
- New typed cases (`.swiftCompilerError`, `.deprecatedDeclaration`, `.noUsage`) cover diagnostics that 4.x silently dropped because the closed enum couldn't represent them.
- `IssueType` now conforms to `Codable` — encodes/decodes as the raw Apple string.

### New: `Issue.location` ([#173](https://github.com/dodobrands/Peekie/pull/173))

```swift
public struct Issue: Equatable, Sendable {
    public let type: IssueType
    public let message: String
    public let location: Location?   // new in 5.0
}

public struct Location: Equatable, Sendable, Codable {
    public let startLine: Int
    public let startColumn: Int?
    public let endLine: Int?
    public let endColumn: Int?
}
```

`startLine` is always present when `location` is non-nil; the other three are independently optional (`xcresulttool` isn't contractually obligated to emit all four).

### New: `File.errors` ([#175](https://github.com/dodobrands/Peekie/pull/175))

`Report`, `Report.Module`, and `Report.File` each expose an `errors` array symmetric to `warnings`:

```swift
public struct File: Hashable {
    public let warnings: [Issue]
    public let errors: [Issue]   // new in 5.0
    ...
}
```

`Report.errors` and `Module.errors` are computed (`files.flatMap(\.errors)`). Errors without `sourceURL` are dropped — same behavior as warnings; see #175 for the open question on a future `Report.unboundIssues` bucket.

### New: `includeTests` flag on `Report.init` ([#179](https://github.com/dodobrands/Peekie/pull/179))

```swift
// 4.x
public init(
    xcresultPath: URL,
    includeCoverage: Bool = true,
    includeWarnings: Bool = true
) async throws

// 5.0
public init(
    xcresultPath: URL,
    includeCoverage: Bool = true,
    includeWarnings: Bool = true,
    includeTests: Bool = true   // new
) async throws
```

Setting `includeTests: false` skips `xcresulttool get test-results tests` — the slowest of the three subprocess calls. `Module.suites` is empty but `files`, `Module.files`, warnings, and errors stay populated.

### Internal: `TotalCoverageDTO` deleted ([#171](https://github.com/dodobrands/Peekie/pull/171))

`CoverageReportDTO` now models the top-level `lineCoverage` field; `Report.init` invokes `xcrun xccov view --report --json` once instead of twice. No public-API change.

---

## Behavior changes (output differs, no rename)

### Warnings on test-less files are no longer dropped ([#176](https://github.com/dodobrands/Peekie/pull/176))

4.x seeded `Module.files` from coverage targets only. A file in a test-less target was invisible, and its warnings vanished. In 5.0 every file with any signal lands in `Report.files`. On `Xcworkspace-26.3-iOS.xcresult`, the raw 13 warnings used to collapse to 4 — they're all 13 now.

### Warnings dedup is dropped ([#174](https://github.com/dodobrands/Peekie/pull/174))

4.x kept one record per unique `(file, message)`. With locations now exposed, three calls to a deprecated function at lines 4, 5, and 12 must produce three records, not one. Counts grow.

### `peekie tests --format json` only emits test data

Even when `Report` is serialized by JSON formatter, only test-shaped data is present because the `tests` subcommand calls `Report(includeCoverage: false, includeWarnings: false, includeTests: true)`. For coverage / warnings / errors, use the dedicated subcommand.

---

## Updating your test snapshots

If you snapshot-test against `Report` or any formatter output downstream, all snapshots will fail on first 5.0 build. Re-record once and verify:

- **More warnings overall** (dedup dropped, test-less files surface).
- **Different module layout** (`Report.files` is now the primary collection; `Module` is a projection).
- **`File.path` / `File.module` populated** when xcresult provided them.
- **`File.errors`** present (empty `[]` for fixtures with no build errors).
- **`Issue.location`** populated when xcresult emitted a `sourceURL` fragment.
- **`Issue.type`** uses the new typed cases (`.swiftCompilerWarning`, `.deprecatedDeclaration`, …).

---

## Related landed PRs

| PR | Issue | Summary |
|---|---|---|
| [#171](https://github.com/dodobrands/Peekie/pull/171) | [#166](https://github.com/dodobrands/Peekie/issues/166) | One `xccov` call per `Report` |
| [#172](https://github.com/dodobrands/Peekie/pull/172) | [#159](https://github.com/dodobrands/Peekie/issues/159) | Open `IssueType` enum |
| [#173](https://github.com/dodobrands/Peekie/pull/173) | [#160](https://github.com/dodobrands/Peekie/issues/160) | `Issue.location` exposure |
| [#174](https://github.com/dodobrands/Peekie/pull/174) | [#161](https://github.com/dodobrands/Peekie/issues/161) | Drop warning dedup |
| [#175](https://github.com/dodobrands/Peekie/pull/175) | [#165](https://github.com/dodobrands/Peekie/issues/165) | Parse `errors[]` |
| [#176](https://github.com/dodobrands/Peekie/pull/176) | [#168](https://github.com/dodobrands/Peekie/issues/168) | File-primary model |
| [#179](https://github.com/dodobrands/Peekie/pull/179) | [#167](https://github.com/dodobrands/Peekie/issues/167) | CLI data-axis restructure |
| [#183](https://github.com/dodobrands/Peekie/pull/183) | [#163](https://github.com/dodobrands/Peekie/issues/163), [#164](https://github.com/dodobrands/Peekie/issues/164) | Regenerated fixtures + regression asserts + normalizer audit |

---

# Migration Guide: 5.x → 6.0

6.0 keeps the CLI surface and most of the SDK shape introduced in 5.0. The single break is on `Report.Module`: it collapses to a thin handle (`{ name }`) and all module-scoped data moves onto `Report` itself, reached via `…(in:)` lookups. The 5.x design materialized `Module.files` as a stored array, which duplicated `File` values across `Report.files` and `Module.files`, made `report.warnings + modules.flatMap(\.warnings)` double-count, and burdened snapshots with two copies of every file's issues.

## SDK — Module is a thin handle

In 5.x, `Module` carried the projection inline:

```swift
public struct Module {
    public let name: String
    public let files: [File]
    public let coverage: Coverage?
    public let rootLevelTests: Set<Suite.RepeatableTest>
    public let suites: [Suite]
    public var warnings: [File.Issue] { files.flatMap(\.warnings) }
    public var errors: [File.Issue] { files.flatMap(\.errors) }
}
```

In 6.0, `Module` is just an identity:

```swift
public struct Module: Hashable {
    public init(name: String)
    public let name: String
}
```

Module-scoped data lives on `Report`:

```swift
public struct Report {
    // existing 5.x storage…
    public let files: [File]
    public let modules: [Module]
    public let coverage: Double?

    // new 6.0 storage — keyed by Module.name
    public let coverageByModule: [String: Coverage]
    public let suitesByModule: [String: [Module.Suite]]
    public let rootLevelTestsByModule: [String: Set<Module.Suite.RepeatableTest>]

    // new 6.0 lookups
    public func files(in module: Module) -> [File]
    public func coverage(of module: Module) -> Coverage?
    public func suites(in module: Module) -> [Module.Suite]
    public func rootLevelTests(in module: Module) -> Set<Module.Suite.RepeatableTest>
    public func warnings(in module: Module) -> [File.Issue]
    public func errors(in module: Module) -> [File.Issue]
}
```

### Migration table

| 5.x | 6.0 |
|---|---|
| `module.files` | `report.files(in: module)` |
| `module.coverage` | `report.coverage(of: module)` |
| `module.suites` | `report.suites(in: module)` |
| `module.rootLevelTests` | `report.rootLevelTests(in: module)` |
| `module.warnings` | `report.warnings(in: module)` |
| `module.errors` | `report.errors(in: module)` |
| `Module(name:, files:, coverage:, rootLevelTests:, suites:)` (5.x init) | `Module(name:)` — projection is on `Report` |

`Module.Suite`, `Module.Suite.RepeatableTest`, and the rest of the nested test types keep their names and layout; only the outer `Module` shrinks.

### Test helpers

`Report.Module.testMake` collapses to `Report.Module.testMake(name:)`. `Report.testMake` gains optional `coverageByModule`, `suitesByModule`, `rootLevelTestsByModule` parameters; the prior memberwise call with `files / modules / coverage` continues to work.

### Why

`report.warnings.count` and `report.modules.flatMap(\.warnings).count` could diverge in 5.x — modules excluded files with `File.module == nil`, but had their own copy of warnings for files they did own. Adding the two without thinking double-counted. With 6.0 the `File` values live in exactly one place (`Report.files`); module-scoped views are pure projections.

## Related landed PRs

| PR | Issue | Summary |
|---|---|---|
| [#204](https://github.com/dodobrands/Peekie/pull/204) | n/a | Fix `pathsByBasename` dup-append when a file lives in multiple coverage targets (drops the multiplier on per-file warning/error counts) |
| [#205](https://github.com/dodobrands/Peekie/pull/205) | n/a | Dedup Apple-emitted `#warning` twins inside `warnings[]` / `errors[]` (collapses paired records to the bucket-matching `IssueType`) |
