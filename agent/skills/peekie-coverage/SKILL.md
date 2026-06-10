---
name: peekie-coverage
description: Extract code coverage from an Xcode `.xcresult` bundle via `peekie coverage`. Trigger when the user asks about coverage from a bundle — e.g. "what's the coverage in /tmp/Tests.xcresult?", "coverage per module please", "covered vs total lines for each file", "give me overall coverage as a percentage I can print in CI", "is coverage above 70%?", "JSON of coverage per file for a custom report". One subcommand, hierarchical modules → files JSON with covered/total line counts.
---

# `peekie coverage`

Emit code coverage from a `.xcresult` bundle as a hierarchical JSON structure (or list).

## Synopsis

```
peekie coverage <xcresult-path> [flags]
```

## Flags

| Flag | Default | Notes |
|---|---|---|
| `<xcresult-path>` | — | **Required** positional. Path to the `.xcresult` bundle. |
| `--format json\|list` | `json` | Output format. |
| `-v, --verbose` | `false` | Debug-level logging to stderr. |

There is **no `--include` flag** on `peekie coverage`. Filter modules/files with `jq`.

## Output shape

### `--format json` (default)

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
        {"name": "Calculator.swift", "path": "/.../Calculator.swift", "coverage": 0.71, "coveredLines": 167, "totalLines": 233}
      ]
    },
    {
      "name": "Networking",
      "coverage": 0.42,
      "coveredLines": 84,
      "totalLines": 200,
      "files": [
        {"name": "Client.swift", "path": "/.../Networking/Client.swift", "coverage": 0.50, "coveredLines": 50, "totalLines": 100},
        {"name": "Endpoint.swift", "path": "/.../Networking/Endpoint.swift", "coverage": 0.34, "coveredLines": 34, "totalLines": 100}
      ]
    }
  ]
}
```

- Top-level `coverage` is overall percentage as `0.0`–`1.0` (multiply by 100 for percent).
- Each module and file carries `coverage`, `coveredLines`, `totalLines`.
- `path` is the absolute source-file path captured at build time.

### `--format list`

Human-readable, indented by module → file. Good for terminal, not for piping.

## Recipes

### Overall coverage as a percentage integer

```bash
peekie coverage Tests.xcresult | jq '.coverage * 100 | floor'
```

### Overall coverage with one decimal place

```bash
peekie coverage Tests.xcresult | jq '(.coverage * 1000 | floor) / 10'
```

`(.coverage * 1000 | floor) / 10` keeps it pure jq — no `bc`, no `printf`. For two decimals, use `* 10000 | floor) / 100`.

### Gate CI on a coverage threshold (≥ 70%)

```bash
if ! peekie coverage Tests.xcresult | jq -e '.coverage >= 0.70' >/dev/null; then
  cov=$(peekie coverage Tests.xcresult | jq -r '(.coverage * 1000 | floor) / 10')
  echo "Coverage below 70% (got ${cov}%)" >&2
  exit 1
fi
```

`jq -e` exits non-zero when the expression is `false` — no `awk` / `bc` needed.

### Per-module summary table

```bash
peekie coverage Tests.xcresult \
  | jq -r '.modules[] | "\(.name)\t\(.coveredLines)/\(.totalLines)\t\((.coverage * 100 | floor))%"'
```

### Files below 50% coverage in a specific module

```bash
peekie coverage Tests.xcresult \
  | jq '.modules[] | select(.name == "Networking") | .files[] | select(.coverage < 0.5)'
```

### Modules sorted by lowest coverage

```bash
peekie coverage Tests.xcresult \
  | jq '.modules | sort_by(.coverage) | .[] | {name, coverage, coveredLines, totalLines}'
```

## Don't

- Don't pass `--include` — it doesn't exist on `peekie coverage`. Filter with `jq`.
- Don't expect tests or warnings here — `peekie coverage` only runs the coverage invocation (`xcrun xccov`). Use the other subcommands for those.
- Don't multiply `.coverage` by anything other than 100 to get a percentage — it's already a `0.0`–`1.0` fraction.
- Don't reach for `xcrun xccov view --report --json` and parse it by hand — `peekie coverage` already runs and normalizes it.

## See also

- `peekie-tests` — test results from the same bundle.
- `peekie-warnings` / `peekie-errors` — build diagnostics from the same bundle.
- `peekie` (umbrella) — CI recipe that fetches errors, warnings, and coverage in one step.
