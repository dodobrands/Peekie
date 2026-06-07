---
name: peekie
description: Parse Xcode `.xcresult` bundles via the `peekie` CLI. Use when the user gives you a path to an `.xcresult` (or asks about test failures / build warnings / coverage and one is on disk) and you need structured data instead of grepping `xcrun xcresulttool` output by hand.
---

# Peekie skill

`peekie` is a CLI for Xcode `.xcresult` bundles. Four data-axis subcommands, each emitting JSON (or list / sonar). Reach for it before composing `xcrun xcresulttool` calls — Peekie is faster, terser, and runs only the `xcresulttool` invocations its subcommand needs.

## Subcommands

```
peekie tests     <xcresult>  [--format json|list|sonar]  default: list
peekie warnings  <xcresult>  [--format json|list]        default: json
peekie errors    <xcresult>  [--format json|list]        default: json
peekie coverage  <xcresult>  [--format json|list]        default: json
```

Each subcommand is single-purpose. To get both warnings and coverage, run two commands and pipe / merge their outputs.

## When to use which

| User goal | Subcommand |
|---|---|
| "Did the tests pass?" / "What failed?" | `peekie tests` |
| "What warnings are in this build?" | `peekie warnings` |
| "Why is the build broken?" / "Show me errors" | `peekie errors` |
| "What's the coverage?" / "Coverage per module" | `peekie coverage` |
| "Generate SonarQube test report" | `peekie tests --format sonar --tests-path …` |

## Output shapes

### `peekie tests --format json`

```json
{
  "coverage": null,
  "modules": [
    {
      "name": "Calculator",
      "suites": [
        {"name": "CalculatorTests", "tests": [{"name": "testAdd()", "status": "success", "durationMs": 12.5, "message": null}]}
      ],
      "files": []
    }
  ]
}
```

`files` and top-level `coverage` are empty/null because `peekie tests` doesn't fetch coverage data. Use `peekie coverage` for that.

### `peekie warnings` (default JSON)

```json
[
  {"file": "Foo.swift", "line": 42, "column": 8, "type": "DeprecatedDeclaration", "message": "'oldFoo()' is deprecated: use bar"},
  {"file": "Foo.swift", "line": 51, "column": 8, "type": "DeprecatedDeclaration", "message": "'oldFoo()' is deprecated: use bar"}
]
```

Flat sorted array. `line` / `column` are `null` when xcresult didn't emit them. Type values are the raw Apple `issueType` strings (`Swift Compiler Warning`, `Swift Compiler Error`, `DeprecatedDeclaration`, `No-usage`, plus anything new Apple adds).

### `peekie errors` (default JSON)

Same shape as `peekie warnings`.

### `peekie coverage` (default JSON)

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

## Recipes

### CI gate: fail when there are build errors

```bash
errors=$(peekie errors Build.xcresult | jq 'length')
if [ "$errors" -gt 0 ]; then
  peekie errors Build.xcresult --format list
  exit 1
fi
```

### Coverage badge value

```bash
peekie coverage Tests.xcresult | jq '.coverage * 100 | floor'
```

### Group warnings by type

```bash
peekie warnings Build.xcresult | jq 'group_by(.type) | map({type: .[0].type, count: length})'
```

### Send only failures to a chat

```bash
peekie tests Tests.xcresult --include failure,mixed --format json | …
```

## Filtering

- `peekie tests --include …` — comma-separated statuses (`success,failure,skipped,expectedFailure,mixed,unknown`). Default: all.
- `peekie warnings` / `peekie errors` have **no `--include` flag**. Filter the JSON output with `jq` or grep the list output.

## Installation

If `peekie` is not on `$PATH`, suggest the user run:

```bash
mise use github:dodobrands/peekie
```

Or download a binary from [Releases](https://github.com/dodobrands/Peekie/releases). Do **not** suggest `swift run peekie …` — that's the contributor flow, not the user flow.

## Don't

- Don't invent `--include-coverage` / `--include-warnings` / `--include-tests` flags on the CLI. They exist on the SDK; on the CLI the subcommand itself determines what gets fetched.
- Don't reach for `xcrun xcresulttool` directly when one of the four subcommands gives you the same data. `peekie warnings` runs **one** `xcresulttool` call; the equivalent hand-rolled pipeline runs three.
- Don't expect `peekie tests` to print coverage or `peekie coverage` to print suites — each subcommand is single-purpose by design.
