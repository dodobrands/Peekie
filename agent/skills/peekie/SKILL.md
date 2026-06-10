---
name: peekie
description: Route Xcode `.xcresult` parsing work to the right `peekie` subcommand. Trigger on broad bundle intent — e.g. "look at this xcresult: /tmp/Build.xcresult", "parse this test bundle", "what's in this build artifact?", "can you summarize this `.xcresult`?", "I have an xcresult from CI, what should I do with it?". Five dedicated sub-skills (`peekie-tests`, `peekie-warnings`, `peekie-errors`, `peekie-coverage`, `peekie-attachments`) cover the data axes; this umbrella picks the right one.
---

# Peekie skill (umbrella)

`peekie` is a CLI for Xcode `.xcresult` bundles. Five data-axis subcommands, each with its own dedicated skill. Reach for one of those instead of composing `xcrun xcresulttool` by hand.

<!-- Last verified: 2026-06 against peekie post-#195 (attachments). Fixtures regenerated on Xcode 26.5. -->

## Subcommand → skill map

| User intent | Sub-skill |
|---|---|
| Test results, failures, smoke checks, "did the tests pass?" | `peekie-tests` |
| Build warnings, deprecations, `#warning(...)` markers | `peekie-warnings` |
| Build errors, "why is the build broken?" | `peekie-errors` |
| Code coverage, "what's the coverage?" | `peekie-coverage` |
| Test attachments — screenshots, logs, blobs | `peekie-attachments` |
| SonarQube generic-test report | `peekie-tests` (uses `--format sonar --tests-path …`) |

If the user asks for a combination (e.g. "show me failures and their attachments", "fail CI on errors and warnings"), pull recipes from each relevant sub-skill and chain them.

## At a glance

```
peekie tests        <xcresult>  [--format json|list|sonar]  default: list
peekie warnings     <xcresult>  [--format json|list]        default: json
peekie errors       <xcresult>  [--format json|list]        default: json
peekie coverage     <xcresult>  [--format json|list]        default: json
peekie attachments  <xcresult>  --output-dir <dir>  [--format json|list]  default: json
```

Every subcommand also accepts `-v` / `--verbose` for debug logging. Each subcommand is single-purpose — to get both warnings and coverage, run two commands and merge their outputs.

## Installation

If `peekie` is not on `$PATH`, suggest:

```bash
mise use github:dodobrands/peekie
```

Or download a binary from [Releases](https://github.com/dodobrands/Peekie/releases). Do **not** suggest `swift run peekie …` — that's the contributor flow, not the user flow.

## Cross-subcommand recipes

### Fail CI on build errors, surface warnings, report coverage

```bash
errors=$(peekie errors Build.xcresult | jq 'length')
warnings=$(peekie warnings Build.xcresult | jq 'length')
coverage=$(peekie coverage Build.xcresult | jq '.coverage * 100 | floor')

echo "errors=$errors warnings=$warnings coverage=${coverage}%"

if [ "$errors" -gt 0 ]; then
  peekie errors Build.xcresult --format list
  exit 1
fi
```

### Save failure attachments as CI artifacts

The naive `peekie attachments … --include failure` leaves every attachment from every test in `--output-dir` — `--include` filters the printed manifest, not files on disk. For a clean per-failure directory, loop over failing test IDs with `--test-id` (each invocation scopes both manifest and on-disk extraction to that one test):

```bash
OUT="$CI_ARTIFACTS/failed-attachments"
mkdir -p "$OUT"

peekie tests Build.xcresult --format json --include failure \
  | jq -r '.modules[].tests[].qualifiedName | split(" / ") | .[1:] | join("/")' \
  | while read -r id; do
      peekie attachments Build.xcresult --output-dir "$OUT" --test-id "$id" --format json >/dev/null
    done
```

The `jq` filter drops the module-name prefix from each `qualifiedName` — `xcresulttool --test-id` (which `peekie attachments` calls under the hood) expects the bare suite-path id without the module. See `peekie-attachments` for details.

### Single CI artifact directory with everything

```bash
ARTIFACTS=$CI_ARTIFACTS
peekie tests      Build.xcresult --format json > "$ARTIFACTS/tests.json"
peekie warnings   Build.xcresult --format json > "$ARTIFACTS/warnings.json"
peekie errors     Build.xcresult --format json > "$ARTIFACTS/errors.json"
peekie coverage   Build.xcresult --format json > "$ARTIFACTS/coverage.json"
peekie attachments Build.xcresult --output-dir "$ARTIFACTS/attachments" --format json > "$ARTIFACTS/attachments.json"
```

## Don't

- Don't reach for `xcrun xcresulttool` directly when one of the five subcommands gives you the same data. Each subcommand runs only the minimum invocations needed.
- Don't expect `--include` to work the same way across subcommands — only `peekie tests` and `peekie attachments` have it; on `attachments` it filters the manifest, not files on disk. `warnings`, `errors`, `coverage` have no `--include`; pipe to `jq` instead.
- Don't mix subcommands in one invocation — each is single-purpose by design. Run multiple commands and merge with `jq`.
- Don't suggest `swift run peekie …` to end-users — that's the contributor flow. Use `mise use github:dodobrands/peekie` or a release binary.
