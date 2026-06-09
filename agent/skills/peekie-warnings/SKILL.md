---
name: peekie-warnings
description: List build warnings from an Xcode `.xcresult` bundle via `peekie warnings`. Trigger when the user asks about warnings — e.g. "what warnings did this build produce?", "show me deprecation warnings in /tmp/Build.xcresult", "group warnings by type", "how many warnings are in this xcresult?", "find all `#warning(...)` markers in my build", "give me JSON of build warnings I can pipe to jq", "are there any actor-isolation warnings?". One subcommand, flat sorted array per warning. Note Apple's `#warning(...)` directives are mis-tagged as `Swift Compiler Error` but appear here, not in `peekie errors`.
---

# `peekie warnings`

List every build warning in a `.xcresult` bundle as a flat sorted JSON array (or human-readable list).

## Synopsis

```
peekie warnings <xcresult-path> [flags]
```

## Flags

| Flag | Default | Notes |
|---|---|---|
| `<xcresult-path>` | — | **Required** positional. Path to the `.xcresult` bundle. |
| `--format json\|list` | `json` | Output format. |
| `-v, --verbose` | `false` | Debug-level logging to stderr. |

There is **no `--include` flag** on `peekie warnings`. Filter with `jq`.

## Output shape

### `--format json` (default)

Flat sorted array, one entry per warning:

```json
[
  {"file": "Foo.swift", "line": 42, "column": 8, "type": "DeprecatedDeclaration", "message": "'oldFoo()' is deprecated: use bar()"},
  {"file": "Bar.swift", "line": 12, "column": 4, "type": "ActorIsolatedCall", "message": "Main actor-isolated initializer cannot be called from outside the actor"},
  {"file": "Calculator.swift", "line": 7, "column": 17, "type": "Swift Compiler Error", "message": "Some warning from Calculator"}
]
```

- `line` / `column` are `null` when xcresult didn't emit them.
- `type` values are the raw Apple `issueType` strings: `Swift Compiler Warning`, `Swift Compiler Error`, `DeprecatedDeclaration`, `No-usage`, `ActorIsolatedCall`, plus whatever new categories Apple adds.

### `--format list`

One line per warning, grouped by file.

## The `#warning(...)` quirk — important

**Xcode mis-tags `#warning("text")` directives as `type: "Swift Compiler Error"`** even though they're warnings and appear in `peekie warnings` output (not `peekie errors`).

The `message` for a `#warning("Some text")` directive is **just the bare string** passed to the directive — `"Some text"` — with no `#warning` wrapper, no quote marks, no syntactic giveaway. Don't try to detect them by grepping the message for `#warning`; the substring isn't there.

**Default assumption: every entry with `type == "Swift Compiler Error"` in `peekie warnings` output is a `#warning(...)` developer marker, not a real defect.** Real compiler errors land in `peekie errors`, not here. Treat the count of `Swift Compiler Error` entries as "TODO markers left in the source"; treat the other types as defects worth prioritizing.

If you absolutely need to confirm, open the source file at `file:line:column` — the line will literally start with `#warning(...)`.

```bash
# Count of #warning markers (since all Swift Compiler Error entries are markers)
peekie warnings Build.xcresult | jq 'map(select(.type == "Swift Compiler Error")) | length'
```

## Recipes

### Count warnings

```bash
peekie warnings Build.xcresult | jq 'length'
```

### Group by type

```bash
peekie warnings Build.xcresult | jq 'group_by(.type) | map({type: .[0].type, count: length})'
```

### Just the deprecation warnings, with file:line

```bash
peekie warnings Build.xcresult \
  | jq -r 'map(select(.type == "DeprecatedDeclaration")) | .[] | "\(.file):\(.line // "?"): \(.message)"'
```

### Triage `#warning(...)` markers separately from real warnings

```bash
peekie warnings Build.xcresult | jq '
  group_by(.type == "Swift Compiler Error" and (.message | test("#warning")))
  | map({kind: (if .[0].type == "Swift Compiler Error" and (.[0].message | test("#warning")) then "#warning markers" else "real warnings" end), count: length})
'
```

## Don't

- Don't pass `--include` — it doesn't exist on `peekie warnings`. Pipe to `jq` to filter by `type`, `file`, or `message`.
- Don't expect errors here — use `peekie errors`. (But do expect `#warning(...)` directives, even though they're tagged `Swift Compiler Error`.)
- Don't trust a raw `length` as a "real warnings" count when `#warning(...)` markers are present — filter them out first or the number misleads.
- Don't reach for `xcrun xcresulttool get build-results` and parse it by hand — `peekie warnings` already runs that and normalizes the output.

## See also

- `peekie-errors` — same shape, but for actual build errors.
- `peekie-tests` — test results from the same bundle.
- `peekie` (umbrella) — combined recipes (errors + warnings + coverage in one CI step).
