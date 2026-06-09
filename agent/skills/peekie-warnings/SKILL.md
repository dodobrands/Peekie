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
  {"file": "Baz.swift", "line": null, "column": null, "type": "Swift Compiler Error", "message": "TODO: remove this stub before shipping #warning(\"TODO: remove this stub before shipping\")"}
]
```

- `line` / `column` are `null` when xcresult didn't emit them.
- `type` values are the raw Apple `issueType` strings: `Swift Compiler Warning`, `Swift Compiler Error`, `DeprecatedDeclaration`, `No-usage`, `ActorIsolatedCall`, plus whatever new categories Apple adds.

### `--format list`

One line per warning, grouped by file.

## The `#warning(...)` quirk — important

**Xcode mis-tags `#warning(...)` directives as `type: "Swift Compiler Error"`** even though they're warnings and appear in `peekie warnings` output (not `peekie errors`). When you see `Swift Compiler Error` entries here, skim the messages — anything matching `…#warning("…")…` is a developer-left TODO marker, not a defect to fix.

Worth calling out separately when interpreting "what kinds of warnings does my build have" — otherwise the count overstates real defects:

```bash
peekie warnings Build.xcresult | jq '
  map(select(.type == "Swift Compiler Error" and (.message | test("#warning"))))
  | length
'
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
