# Peekie

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fdodobrands%2FPeekie%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/dodobrands/Peekie)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fdodobrands%2FPeekie%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/dodobrands/Peekie)
[![](https://github.com/dodobrands/Peekie/actions/workflows/unittest.yml/badge.svg)](https://github.com/dodobrands/Peekie/actions/workflows/unittest.yml)
[![](https://img.shields.io/badge/XCTest-Supported-success)](https://developer.apple.com/documentation/xctest)
[![](https://img.shields.io/badge/Swift%20Testing-Supported-success)](https://developer.apple.com/xcode/swift-testing/)

<p align="center">
  <img width="128" height="128" alt="Peekie Logo" src=".github/peekie-logo.png" />
</p>

**Peekie** is a CLI for Xcode `.xcresult` bundles. One subcommand per data type — `tests`, `warnings`, `errors`, `coverage` — each emitting machine-readable JSON (or a human-readable list, or SonarQube XML). Designed to be reached from CI scripts and **LLM coding agents** (Claude Code, Cursor) without re-explaining how `xcresulttool` works every time.

> Upgrading from 4.x? Read [**MIGRATION.md**](MIGRATION.md).

## Table of Contents

- [Install](#install)
- [CLI](#cli)
  - [`peekie tests`](#peekie-tests)
  - [`peekie warnings`](#peekie-warnings)
  - [`peekie errors`](#peekie-errors)
  - [`peekie coverage`](#peekie-coverage)
  - [`peekie attachments`](#peekie-attachments)
- [Agent integration](#agent-integration)
- [Library (PeekieSDK)](#library-peekiesdk)
- [License](#license)

## Install

The fastest way to get the `peekie` binary on your `PATH` is via [mise](https://mise.jdx.dev/):

```bash
mise use github:dodobrands/peekie
```

Other options: [Homebrew tap](https://github.com/dodobrands/homebrew-tap) (coming soon), or download a pre-built binary from the [Releases page](https://github.com/dodobrands/Peekie/releases).

## CLI

Five data-axis subcommands. Each runs only the `xcrun` calls it needs.

```
peekie tests        <xcresult>  [--format json|list|sonar]  default: list
peekie warnings     <xcresult>  [--format json|list]        default: json
peekie errors       <xcresult>  [--format json|list]        default: json
peekie coverage     <xcresult>  [--format json|list]        default: json
peekie attachments  <xcresult>  --output-dir <dir> [--format json|list]  default: json
```

### `peekie tests`

Test results, with status filtering and SonarQube export.

```bash
# Human-readable, all statuses
peekie tests Tests.xcresult

# Only failures and flaky tests
peekie tests Tests.xcresult --include failure,mixed

# JSON for a dashboard
peekie tests Tests.xcresult --format json > tests.json

# SonarQube generic test execution XML
peekie tests Tests.xcresult --format sonar --tests-path Tests > sonar-tests.xml
```

**Options:** `--include` (comma-separated statuses), `--include-device-details`, `--tests-path` (required with `--format sonar`), `--attachments skip|export` + `--attachments-to <dir>` (embeds attachment metadata into each test in the JSON output; required together when exporting).

### `peekie warnings`

Flat JSON array of build warnings. Pipe to `jq` for filtering.

```bash
peekie warnings Tests.xcresult
# [
#   {"file":"Foo.swift","line":42,"column":8,"type":"DeprecatedDeclaration","message":"'oldFoo()' is deprecated: use bar"},
#   ...
# ]

# Group by type
peekie warnings Tests.xcresult | jq 'group_by(.type) | map({type: .[0].type, count: length})'

# Human-readable
peekie warnings Tests.xcresult --format list
# Foo.swift:42:8 [DeprecatedDeclaration] 'oldFoo()' is deprecated
```

### `peekie errors`

Same shape as `warnings`, for the `errors[]` array. Use as a build-failed gate:

```bash
errors=$(peekie errors Tests.xcresult | jq 'length')
[ "$errors" -gt 0 ] && exit 1
```

### `peekie coverage`

```bash
# JSON for a dashboard
peekie coverage Tests.xcresult
# {"coverage": 0.6234, "modules": [{"name":"Calculator","coverage":0.71,"files":[…]}, …]}

# Total in one line
peekie coverage Tests.xcresult | jq '.coverage'
# 0.6234

# Padded table
peekie coverage Tests.xcresult --format list
# Calculator       71.6%  (167/233)
# StringUtils      84.0%  (42/50)
# total            62.3%
```

### `peekie attachments`

Exports `XCTAttachment` / Swift Testing `Attachment.record(...)` payloads to a directory and emits a flat JSON array describing each one (which test it came from, suggested filename, MIME type, whether it's tied to a failure).

```bash
# Export every attachment in the bundle
peekie attachments Tests.xcresult --output-dir ./attachments
# [
#   {
#     "qualifiedName": "ExamplesTests / ExampleSUITests / withAttachment()",
#     "name": "Calculation Result_0_<uuid>.txt",
#     "exportedFileName": "<uuid>.txt",
#     "path": "./attachments/<uuid>.txt",
#     "contentType": "text/plain",
#     "isAssociatedWithFailure": false,
#     "repetitionNumber": 1
#   },
#   ...
# ]

# Only attachments from failing tests
peekie attachments Tests.xcresult --output-dir ./attachments --include failure

# A single test by identifier
peekie attachments Tests.xcresult --output-dir ./attachments --test-id "ExamplesTests/ExampleSUITests/withAttachment()"

# Human-readable
peekie attachments Tests.xcresult --output-dir ./attachments --format list
```

**Options:** `--output-dir` (required), `--test-id`, `--include` (comma-separated statuses), `--format json|list`.

Need the attachments embedded into each test (instead of a flat list)? Use `peekie tests --attachments export --attachments-to <dir> --format json` — each test gains an `attachments[]` array in its JSON node.

## Agent integration

Peekie is intentionally shaped to be reachable by LLM coding agents. The four data-axis subcommands plus `--format json` are orthogonal so an agent can compose calls without inventing arguments.

This repo also ships as a **plugin marketplace**, so you can install the skill in one command.

### Claude Code

```bash
/plugin marketplace add dodobrands/Peekie
/plugin install peekie
```

### Cursor

Teams / Enterprise: add as a team marketplace in settings.

Individual: clone and symlink the rule into your project:

```bash
git clone https://github.com/dodobrands/Peekie.git ~/.peekie-plugin
mkdir -p .cursor/rules
ln -s ~/.peekie-plugin/agent/rules/peekie.mdc .cursor/rules/peekie.mdc
```

The skill lives in [`agent/`](agent/); the marketplace catalog is at [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).

## Library (`PeekieSDK`)

If you need to embed parsing in your own Swift code (instead of shelling out to the CLI), depend on `PeekieSDK`:

```swift
.package(url: "https://github.com/dodobrands/Peekie.git", from: "5.0.0")
```

The model is **File-primary**: `Report.files` is the source of truth; `Report.modules` is a projection grouping files by target name.

```swift
import PeekieSDK

let report = try await Report(xcresultPath: URL(fileURLWithPath: "/path/to.xcresult"))

// All warnings, anywhere in the bundle
for issue in report.warnings {
    print("\(issue.type.rawValue): \(issue.message)")
}

// Files in a specific target
let bonusesFiles = report.modules.first { $0.name == "Bonuses" }?.files ?? []

// Files without a known target (test-less targets, project-level issues)
let untargeted = report.files.filter { $0.module == nil }
```

`Report.init` accepts `includeCoverage`, `includeWarnings`, `includeTests` flags (all default `true`). Disable what you don't need to skip the corresponding `xcrun` calls.

For the full model — `File`, `Module`, `Suite`, `Issue.Location`, `IssueType` — see the source under [`Sources/PeekieSDK/Models/`](Sources/PeekieSDK/Models/) and the `tests` / `warnings` / `coverage` formatter implementations under [`Sources/PeekieSDK/Formatters/`](Sources/PeekieSDK/Formatters/).

### Test fixtures

`.xcresult` bundles under [`Tests/PeekieTests/Resources/`](Tests/PeekieTests/Resources/) are generated by the [swift-tests-example](https://github.com/dodobrands/swift-tests-example) repo. To regenerate after Xcode updates, follow that repo's instructions.

## License

This code is released under the Apache License. See [LICENSE](LICENSE) for more information.
