---
name: peekie
description: Parse Xcode `.xcresult` bundles via the `peekie` CLI. Use when the user gives you a path to an `.xcresult`, asks "did the tests pass?" / "what failed?" / "show me build warnings" / "what's the coverage?" / "extract failure screenshots", or wants structured JSON from a test bundle instead of grepping `xcrun xcresulttool` output by hand. Five subcommands cover tests, warnings, errors, coverage, and attachments.
---

# Peekie skill

`peekie` is a CLI for Xcode `.xcresult` bundles. Five data-axis subcommands, each emitting JSON (or list / sonar). Reach for it before composing `xcrun xcresulttool` calls — Peekie is faster, terser, and runs only the `xcresulttool` invocations its subcommand needs.

<!-- Last verified: 2026-06 against peekie post-#195 (attachments). Fixtures regenerated on Xcode 26.5. -->

## Subcommands at a glance

```
peekie tests        <xcresult>  [--format json|list|sonar]  default: list
peekie warnings     <xcresult>  [--format json|list]        default: json
peekie errors       <xcresult>  [--format json|list]        default: json
peekie coverage     <xcresult>  [--format json|list]        default: json
peekie attachments  <xcresult>  --output-dir <dir>  [--format json|list]  default: json
```

Every subcommand also accepts `-v` / `--verbose` for debug logging. Each subcommand is single-purpose — to get both warnings and coverage, run two commands and merge their outputs.

## `peekie tests`

The default JSON shape is a **flat per-module `tests` array** with fully-qualified test names. Root-level `@Test` functions (no enclosing `@Suite`), nested `@Suite` types, and backtick-escaped names all appear here.

```bash
peekie tests Tests.xcresult --format json
```

```json
{
  "modules": [
    {
      "name": "ExamplesTests",
      "files": [],
      "tests": [
        {"qualifiedName": "ExamplesTests / 2 + 3 = 5", "status": "success", "durationMs": 11.99},
        {"qualifiedName": "ExamplesTests / ExampleSUITests / failure()", "status": "failure", "durationMs": 8.34, "message": "Expected 5.0 but got 6.0"},
        {"qualifiedName": "ExamplesTests / OuterSuite / InnerSuite / DeeplyNestedSuite / deeplyNestedSuccess()", "status": "success", "durationMs": 1.2}
      ]
    }
  ]
}
```

- `qualifiedName` is the canonical full path joined by ` / ` (with spaces around the slash). Module → suite path (if any) → test name. Use it as the stable identifier when correlating tests across runs.
- `status` is one of `success`, `failure`, `expectedFailure`, `skipped`, `mixed`, `unknown`.
- `message` only appears on tests that produced a failure / skip / mixed message.
- `tests` is empty when no tests of the included statuses survive filtering.

### Flags

- `--include <statuses>` — comma-separated, defaults to all. e.g. `--include failure,mixed` for just-the-broken-things.
- `--include-device-details true` — when matrix runs put device names in test names (e.g. `testFoo() [iPhone 15 Pro]`). Off by default.
- `--attachments export --attachments-to <dir>` — adds an `attachments` array under each test in the JSON. Extracts attachment files to `<dir>` on disk. Default is `skip` (no extraction, no `attachments` field).
- `--format sonar --tests-path <path>` — SonarQube generic-test report. `--tests-path` is **required** when using sonar (points at the source tree for file/line correlation).
- `--verbose` — debug logging to stderr.

### Sample with attachments

```bash
peekie tests Tests.xcresult --format json --attachments export --attachments-to /tmp/att
```

Each test gains an optional `attachments` array:

```json
{
  "qualifiedName": "ExamplesTests / ExampleSUITests / withAttachment()",
  "status": "success",
  "durationMs": 8.34,
  "attachments": [
    {
      "name": "Calculation Result.txt",
      "exportedFileName": "67676173-…-396.txt",
      "path": "/tmp/att/67676173-…-396.txt",
      "contentType": "text/plain",
      "isAssociatedWithFailure": false,
      "repetitionNumber": 1
    }
  ]
}
```

## `peekie attachments`

Standalone subcommand for extracting and listing attachments. `--output-dir` is **required** — there is no inspect-only mode; the underlying `xcresulttool` always writes files to disk.

```bash
peekie attachments Tests.xcresult --output-dir /tmp/att
```

```json
[
  {
    "qualifiedName": "ExamplesTests / ExampleSUITests / failureWithAttachment()",
    "name": "Failure context.txt",
    "exportedFileName": "DA864376-…-FDD5.txt",
    "path": "/tmp/att/DA864376-…-FDD5.txt",
    "contentType": "text/plain",
    "isAssociatedWithFailure": false,
    "repetitionNumber": 1,
    "configurationName": "Test Scheme Action"
  }
]
```

Flat, sorted by `qualifiedName`. `contentType` is derived from the filename extension via `UTType.preferredMIMEType` — for attachments whose `exportedFileName` has no extension it is `null`.

### Flags

- `--include <statuses>` — comma-separated test statuses. **Filters the JSON / list output only — does NOT filter files written to `--output-dir`.** The underlying `xcrun xcresulttool export attachments` always materializes every attachment in the bundle on disk; peekie then filters the manifest it prints. If the user wants the directory itself to contain only attachments from failing (or otherwise filtered) tests, see the recipe below.
- `--test-id <id>` — extract attachments for just one test. Accepts either the bare identifier (`ExampleSUITests/foo()`) or the full `test://com.apple.xcode/...` URL. **Unlike `--include`, this DOES filter files on disk** — `xcresulttool` only extracts attachments belonging to that single test.
- `--format list` — human-readable grouping (one section per test, one line per attachment).
- `--verbose` — debug logging.

### Recipe: clean per-failure attachments on disk

`--include failure` alone leaves every attachment from every test in `--output-dir`. To make the directory contain only failure-test attachments, iterate over failing test IDs and call `peekie attachments --test-id <id>` per test:

```bash
OUT=/tmp/failed-attachments
mkdir -p "$OUT"
peekie tests Tests.xcresult --format json --include failure \
  | jq -r '.modules[].tests[] | .qualifiedName | sub(" / "; "/"; "g")' \
  | while read -r id; do
      peekie attachments Tests.xcresult --output-dir "$OUT" --test-id "$id" --format json
    done
```

Apple's own `xcresulttool export attachments --only-failures` looks like it should solve this, but it filters on `isAssociatedWithFailure` — a field that's frequently `false` even on attachments recorded inside a failing test (only set by `XCTAttachment.lifetime = .deleteOnSuccess` or the equivalent explicit hint). So `--only-failures` often returns an empty manifest. The per-test-id loop above is what actually surfaces "attachments belonging to failing tests".

## `peekie warnings`

```bash
peekie warnings Build.xcresult --format json
```

Flat sorted array, one entry per warning:

```json
[
  {"file": "Foo.swift", "line": 42, "column": 8, "type": "DeprecatedDeclaration", "message": "'oldFoo()' is deprecated: use bar()"},
  {"file": "Bar.swift", "line": 12, "column": 4, "type": "ActorIsolatedCall", "message": "Main actor-isolated initializer cannot be called from outside the actor"}
]
```

- `line` / `column` are `null` when xcresult didn't emit them.
- `type` values are the raw Apple `issueType` strings: `Swift Compiler Warning`, `Swift Compiler Error`, `DeprecatedDeclaration`, `No-usage`, `ActorIsolatedCall`, plus anything new Apple adds.
- `--verbose` for debug logging.

`peekie warnings` does not have an `--include` flag — pipe to `jq` if you need to filter by type.

## `peekie errors`

Same shape as `peekie warnings`. Use this when build broke.

## `peekie coverage`

```bash
peekie coverage Tests.xcresult --format json
```

```json
{
  "coverage": 0.6234,
  "modules": [
    {
      "name": "Calculator",
      "coverage": 0.71,
      "coveredLines": 167,
      "totalLines": 233,
      "files": [
        {"name": "Calculator.swift", "path": "/…/Calculator.swift", "coverage": 0.71, "coveredLines": 167, "totalLines": 233}
      ]
    }
  ]
}
```

Top-level `coverage` is the overall percentage (0.0-1.0). Use this — it's the only subcommand that fetches coverage data.

## When to use which

| User goal | Subcommand |
|---|---|
| "Did the tests pass?" / "What failed?" | `peekie tests` |
| "What warnings are in this build?" | `peekie warnings` |
| "Why is the build broken?" / "Show me errors" | `peekie errors` |
| "What's the coverage?" / "Coverage per module" | `peekie coverage` |
| "Extract failure screenshots" / "Where are the attachments?" | `peekie attachments` |
| "Generate SonarQube test report" | `peekie tests --format sonar --tests-path …` |

## Recipes

### Fail CI on build errors

```bash
errors=$(peekie errors Build.xcresult | jq 'length')
if [ "$errors" -gt 0 ]; then
  peekie errors Build.xcresult --format list
  exit 1
fi
```

### Coverage as percentage

```bash
peekie coverage Tests.xcresult | jq '.coverage * 100 | floor'
```

### Group warnings by type

```bash
peekie warnings Build.xcresult | jq 'group_by(.type) | map({type: .[0].type, count: length})'
```

### Send only failures to a chat

```bash
peekie tests Tests.xcresult --include failure,mixed --format json | jq '.modules[].tests'
```

### Save failure attachments as CI artifacts

The naive form `peekie attachments Build.xcresult --output-dir <dir> --include failure` leaves every attachment in the directory (not only those from failing tests) — `--include` is a manifest filter, not a disk filter. For a clean per-failure directory, loop per failing test ID:

```bash
OUT="$CI_ARTIFACTS/failed-attachments"
mkdir -p "$OUT"
peekie tests Build.xcresult --format json --include failure \
  | jq -r '.modules[].tests[].qualifiedName | sub(" / "; "/"; "g")' \
  | while read -r id; do
      peekie attachments Build.xcresult --output-dir "$OUT" --test-id "$id" --format json >/dev/null
    done
```

Each `peekie attachments --test-id <id>` only materializes attachments for that single test.

### Test results JSON with attachments inlined

```bash
peekie tests Tests.xcresult --format json --attachments export --attachments-to /tmp/att \
  | jq '.modules[].tests[] | select(.attachments)'
```

### Tests with device labels in matrix runs

```bash
peekie tests Tests.xcresult --format json --include-device-details true
```

Device names become part of `qualifiedName` (e.g. `… / testFoo() [iPhone 15 Pro]`). Useful for de-duplicating identical test names across simulators.

## Installation

If `peekie` is not on `$PATH`, suggest the user run:

```bash
mise use github:dodobrands/peekie
```

Or download a binary from [Releases](https://github.com/dodobrands/Peekie/releases). Do **not** suggest `swift run peekie …` — that's the contributor flow, not the user flow.

## Don't

- Don't invent `--include-coverage` / `--include-warnings` / `--include-tests` flags on the CLI. They exist on the SDK; on the CLI the subcommand itself determines what gets fetched.
- Don't reach for `xcrun xcresulttool` directly when one of the five subcommands gives you the same data. Each subcommand runs only the minimum invocations needed.
- Don't expect `peekie tests` to surface attachments by default — `--attachments export --attachments-to <dir>` is opt-in to keep the default fast.
- Don't expect `peekie tests` to print coverage or `peekie coverage` to print suites — each subcommand is single-purpose by design.
- Don't write `jq` queries against a nested `suites` / `rootLevelTests` / `nestedSuites` JSON shape — that's the older `JSONFormatter.Grouping.bySuite` SDK output, not what the CLI emits. CLI `peekie tests --format json` is always the flat `tests[]` shape with `qualifiedName`.
- Don't pass `--output-dir` to `peekie attachments` and expect it to be optional — it's required, and `xcresulttool` will always materialize files there.
- Don't try to filter `peekie warnings` / `peekie errors` / `peekie coverage` with `--include` — that flag only exists on `tests` and `attachments`. Filter with `jq` instead.
- Don't trust `peekie attachments --include failure` to keep the `--output-dir` clean. `--include` only filters the JSON / list output; the directory still gets every attachment in the bundle. For a clean per-failure directory, loop with `--test-id` (see recipe above).
