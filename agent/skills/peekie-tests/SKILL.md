---
name: peekie-tests
description: Parse and format test results from an Xcode `.xcresult` bundle via `peekie tests`. Trigger when the user asks anything about test outcomes from a bundle — e.g. "did the tests pass in /tmp/Tests.xcresult?", "show me failing tests from this build", "what tests failed?", "which tests were skipped?", "give me a JSON list of every test in this xcresult", "generate a SonarQube test report from this bundle", "I need the fully-qualified names of failing tests for CI", "extract test results plus their attachments". Covers the `tests` subcommand exhaustively: filtering by status, device labels for matrix runs, attachments export, sonar generic-test format.
---

# `peekie tests`

Parse a `.xcresult` bundle and emit per-module test results with fully-qualified test names, durations, and failure messages.

## Synopsis

```
peekie tests <xcresult-path> [flags]
```

## Flags

| Flag | Default | Notes |
|---|---|---|
| `<xcresult-path>` | — | **Required** positional. Path to the `.xcresult` bundle. |
| `--format json\|list\|sonar` | `list` | Output format. Default differs from sister subcommands — `tests` defaults to `list`, others default to `json`. |
| `--include <statuses>` | all 6 (`success,failure,expectedFailure,skipped,mixed,unknown`) | Comma-separated list. Filters which tests appear in output. Status names are case-sensitive. |
| `--include-device-details true\|false` | `false` | When `true`, device names appear in `qualifiedName` (e.g. `… / testFoo() [iPhone 15 Pro]`). Useful for matrix runs. |
| `--tests-path <path>` | — | **Required** with `--format sonar`. Source-tree path used for file/line correlation in the SonarQube report. Ignored for `json` / `list`. |
| `--attachments skip\|export` | `skip` | When `export`, each test JSON gains an `attachments` array AND files are extracted to disk. |
| `--attachments-to <dir>` | — | **Required** with `--attachments export`. Directory where attachment files are written. |
| `-v, --verbose` | `false` | Debug-level logging to stderr. |

## Output shape

### `--format json` (default-flat structure)

Per-module `tests` array with fully-qualified names. Root-level `@Test` functions (no enclosing `@Suite`), nested `@Suite` types, and backtick-escaped names all appear flat in this array.

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

- `qualifiedName` is the canonical full path joined by ` / ` (literal space-slash-space). Module → suite path (if any) → test name. Use this as the stable identifier when correlating tests across runs.
- `status` is one of `success`, `failure`, `expectedFailure`, `skipped`, `mixed`, `unknown`.
- `message` only appears on tests that produced a failure / skip / mixed message.
- `tests` is empty when no tests of the included statuses survive filtering.

### `--format list`

Human-readable. One line per test, grouped by module. Good for terminal scanning, not for piping to `jq`.

### `--format sonar`

SonarQube generic-test report (XML). Requires `--tests-path`. Use only when feeding SonarQube directly.

### `--attachments export` JSON addition

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

## Recipes

### Just-the-broken-things

```bash
peekie tests Tests.xcresult --include failure,mixed --format json | jq '.modules[].tests'
```

### Count failures across modules

```bash
peekie tests Tests.xcresult --include failure --format json \
  | jq '[.modules[].tests[]] | length'
```

### Fully-qualified failure names for a Slack/TG summary

```bash
peekie tests Tests.xcresult --include failure --format json \
  | jq -r '.modules[].tests[] | "- " + .qualifiedName + ": " + (.message // "")'
```

### Tests with device labels in matrix runs

```bash
peekie tests Tests.xcresult --format json --include-device-details true
```

Device names become part of `qualifiedName` (e.g. `… / testFoo() [iPhone 15 Pro]`). Useful for de-duplicating identical test names across simulators.

### SonarQube report for CI

```bash
peekie tests Tests.xcresult --format sonar --tests-path ./Sources > sonar-tests.xml
```

### Inline attachments in the test JSON

```bash
peekie tests Tests.xcresult --format json --attachments export --attachments-to /tmp/att \
  | jq '.modules[].tests[] | select(.attachments)'
```

## Don't

- Don't pass `--format sonar` without `--tests-path` — it'll error out at runtime.
- Don't pass `--attachments export` without `--attachments-to` — same.
- Don't expect a nested `suites` / `rootLevelTests` / `nestedSuites` JSON shape — the CLI always emits the flat `tests[]` shape with `qualifiedName`. The nested shape is the older `JSONFormatter.Grouping.bySuite` SDK output, not what the CLI prints.
- Don't try to fetch coverage or warnings from `peekie tests` — it only runs the test-results invocation. Use `peekie coverage` / `peekie warnings` for those.
- Don't filter by hand-split `qualifiedName` strings if you only need a status filter — use `--include` and let the CLI do it.

## See also

- `peekie-attachments` — standalone manifest + per-test extraction with `--test-id`.
- `peekie-warnings`, `peekie-errors` — build-side diagnostics from the same bundle.
- `peekie-coverage` — coverage from the same bundle.
- `peekie` (umbrella) — cross-subcommand recipes (e.g. saving failure attachments as CI artifacts).
