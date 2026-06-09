---
name: peekie-errors
description: List build errors from an Xcode `.xcresult` bundle via `peekie errors`. Trigger when the user asks about why a build broke or wants structured error output — e.g. "why is the build broken in /tmp/Build.xcresult?", "show me build errors from this CI run", "how many errors are there in this xcresult?", "give me JSON of compilation errors I can pipe to jq", "fail my CI step if errors > 0", "first three errors with file and line, please". One subcommand, flat sorted array per error, same shape as `peekie warnings`.
---

# `peekie errors`

List every build error in a `.xcresult` bundle as a flat sorted JSON array (or human-readable list). Same shape as `peekie warnings`.

## Synopsis

```
peekie errors <xcresult-path> [flags]
```

## Flags

| Flag | Default | Notes |
|---|---|---|
| `<xcresult-path>` | — | **Required** positional. Path to the `.xcresult` bundle. |
| `--format json\|list` | `json` | Output format. |
| `-v, --verbose` | `false` | Debug-level logging to stderr. |

There is **no `--include` flag** on `peekie errors`. Filter with `jq`.

## Output shape

### `--format json` (default)

Flat sorted array, one entry per error:

```json
[
  {"file": "AppDelegate.swift", "line": 87, "column": 5, "type": "Swift Compiler Error", "message": "Cannot find 'FooBar' in scope"},
  {"file": "Network/Client.swift", "line": 154, "column": 12, "type": "Swift Compiler Error", "message": "Value of type 'URLSession' has no member 'asyncData'"}
]
```

- `line` / `column` are `null` when xcresult didn't emit them.
- `type` is the raw Apple `issueType` string — most commonly `Swift Compiler Error`, but anything in the errors bucket appears here.

Note: unlike `peekie warnings`, you should not see `#warning(...)` markers here — those land in `peekie warnings` even though Apple tags them `Swift Compiler Error` (see `peekie-warnings`).

### `--format list`

One line per error, grouped by file.

## Recipes

### Fail CI on any error

```bash
errors=$(peekie errors Build.xcresult | jq 'length')
if [ "$errors" -gt 0 ]; then
  peekie errors Build.xcresult --format list
  exit 1
fi
```

### Print first three errors with `file:line`

```bash
peekie errors Build.xcresult \
  | jq -r '.[:3] | .[] | "\(.file):\(.line // "?"): \(.message)"'
```

### Group errors by file

```bash
peekie errors Build.xcresult | jq 'group_by(.file) | map({file: .[0].file, count: length})'
```

### Just the first error's message (handy for build-failure notifications)

```bash
peekie errors Build.xcresult | jq -r '.[0].message // "no errors"'
```

## Don't

- Don't pass `--include` — it doesn't exist on `peekie errors`. Pipe to `jq`.
- Don't expect warnings here — even `#warning(...)` developer markers (which Apple tags `Swift Compiler Error`) appear in `peekie warnings`, not here. If you want every diagnostic, run both commands.
- Don't reach for `xcrun xcresulttool get build-results` and parse it by hand — `peekie errors` already runs that and normalizes the output.
- Don't try `--format sonar` — only `peekie tests` supports it.

## See also

- `peekie-warnings` — same shape, but for warnings (including the `#warning(...)` quirk).
- `peekie-tests` — test failures from the same bundle (separate from build errors).
- `peekie` (umbrella) — CI recipe that checks errors, warnings, and coverage in one step.
