---
name: peekie-attachments
description: Extract and list test attachments (screenshots, logs, blobs) from an Xcode `.xcresult` bundle via `peekie attachments`. Trigger when the user asks about attached files in a bundle — e.g. "extract failure screenshots from /tmp/Tests.xcresult to /tmp/out", "save attachments for a single test", "what's attached to my failing tests?", "dump every attachment from this xcresult", "give me a manifest of attachments with file paths and content types", "I need just the attachments for `ExampleSUITests/failure()`". `--output-dir` is required. Note `--include` filters the printed manifest, NOT files written to disk — use `--test-id` to scope disk writes.
---

# `peekie attachments`

Extract attachment files from a `.xcresult` bundle to a directory and print a manifest with `qualifiedName`, file path, content type, and failure-association metadata.

## Synopsis

```
peekie attachments <xcresult-path> --output-dir <dir> [flags]
```

`--output-dir` is **required** — there is no inspect-only mode; the underlying `xcrun xcresulttool export attachments` always writes files to disk.

## Flags

| Flag | Default | Notes |
|---|---|---|
| `<xcresult-path>` | — | **Required** positional. Path to the `.xcresult` bundle. |
| `--output-dir <dir>` | — | **Required**. Directory where attachment files are extracted. Created if missing. |
| `--test-id <id>` | — | Limit extraction to a single test. Accepts the bare identifier (`ExampleSUITests/foo()`) or the full `test://com.apple.xcode/...` URL. **This DOES filter files on disk** — `xcresulttool` only writes that test's attachments. |
| `--include <statuses>` | all 6 (`success,failure,expectedFailure,skipped,mixed,unknown`) | Comma-separated test statuses. **Filters the printed JSON / list manifest only — does NOT filter files on disk.** |
| `--format json\|list` | `json` | Output format for the printed manifest. |
| `-v, --verbose` | `false` | Debug-level logging to stderr. |

## Output shape

### `--format json` (default)

Flat array, sorted by `qualifiedName`:

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
  },
  {
    "qualifiedName": "ExamplesTests / ExampleSUITests / withAttachment()",
    "name": "Calculation Result.txt",
    "exportedFileName": "67676173-…-396.txt",
    "path": "/tmp/att/67676173-…-396.txt",
    "contentType": "text/plain",
    "isAssociatedWithFailure": false,
    "repetitionNumber": 1,
    "configurationName": "Test Scheme Action"
  }
]
```

- `qualifiedName` matches the same convention as `peekie tests` — ` / ` joined, module → suite path → test name.
- `name` is the human-facing attachment label (often the original filename or `XCTAttachment` name).
- `exportedFileName` is the UUID-based filename `xcresulttool` actually writes to disk.
- `path` is `<output-dir>/<exportedFileName>` — ready to read or upload.
- `contentType` is derived from the extension via `UTType.preferredMIMEType` — `null` when `exportedFileName` has no extension.
- `isAssociatedWithFailure` is set by `XCTAttachment.lifetime = .deleteOnSuccess` or an equivalent explicit hint; it's often `false` even for attachments captured inside a failing test (see "Don't" below).
- `repetitionNumber` is `1` unless test repeated under retry-on-failure.

### `--format list`

Grouped by test (one section per `qualifiedName`, one line per attachment). Good for terminal scanning.

## Recipes

### Dump everything to a CI artifact directory

```bash
peekie attachments Tests.xcresult --output-dir "$CI_ARTIFACTS/attachments"
```

### Per-failure clean directory (the canonical recipe)

`--include failure` on its own leaves every attachment from every test in `--output-dir`. To get a directory tree where each failing test has its own subdir of attachments, use the bundled helper script:

```bash
scripts/extract-failure-attachments.sh Tests.xcresult /tmp/failed-attachments
```

The script (in this skill's `scripts/` directory) iterates over failing test IDs, sanitizes each into a safe directory name, and runs `peekie attachments --test-id` per failure into its own subdirectory. Inline equivalent — useful if you want to inspect or adapt the loop:

```bash
OUT=/tmp/failed-attachments
mkdir -p "$OUT"

peekie tests Tests.xcresult --format json --include failure \
  | jq -r '.modules[].tests[].qualifiedName | split(" / ") | .[1:] | join("/")' \
  | while read -r id; do
      slug=$(printf '%s' "$id" | tr '/()' '___' | tr -s '_')
      mkdir -p "$OUT/$slug"
      peekie attachments Tests.xcresult --output-dir "$OUT/$slug" --test-id "$id" --format json >/dev/null
    done
```

Two non-obvious bits:

- The `jq` expression drops the leading module segment from each `qualifiedName`. `xcresulttool --test-id` (which `peekie attachments` invokes under the hood) expects the bare suite-path identifier (e.g. `ExampleSUITests/failureWithAttachment()`), not the module-prefixed full path. Passing the prefixed form returns `Error: Failed to find test with the provided identifier`.
- Each iteration writes its own `manifest.json` directly into `--output-dir`. Reusing one shared `$OUT` across iterations fails on the second `--test-id` with `Failed to generate manifest.json: file already exists` — that's why both the script and the inline loop create a per-test subdirectory.

Apple's own `xcresulttool export attachments --only-failures` looks like it should solve this, but it filters on `isAssociatedWithFailure` — a field that's frequently `false` even for attachments recorded inside a failing test (only set by `XCTAttachment.lifetime = .deleteOnSuccess` or the equivalent explicit hint). So `--only-failures` often returns an empty manifest. The per-`--test-id` loop above is what actually surfaces "attachments belonging to failing tests".

### Attachments for one specific test

```bash
peekie attachments Tests.xcresult \
  --output-dir /tmp/att \
  --test-id "ExampleSUITests/failure()"
```

### Just the file paths, for `cp`/`scp`/upload

```bash
peekie attachments Tests.xcresult --output-dir /tmp/att | jq -r '.[].path'
```

### Filter the manifest to failures (files on disk are still full set)

```bash
peekie attachments Tests.xcresult --output-dir /tmp/att --include failure
```

Use this when you want the JSON narrowed but don't care that the directory holds everything. For a clean directory, use the per-`--test-id` loop above.

## Don't

- Don't omit `--output-dir` — it's required. There's no inspect-only mode.
- Don't expect `--include failure` to leave only failure-test attachments on disk — it only filters the printed manifest. Use `--test-id` per test for a clean disk subset.
- Don't trust `xcrun xcresulttool export attachments --only-failures` as a shortcut — it filters on `isAssociatedWithFailure`, which is rarely set unless you've used `XCTAttachment.lifetime = .deleteOnSuccess`. Use the per-`--test-id` loop instead.
- Don't pass `--test-id` and `--include` together expecting them to AND-combine on disk — `--test-id` scopes extraction to one test, `--include` filters the printed JSON manifest. They operate at different layers; combining them is fine but rarely useful.
- Don't reach for `xcrun xcresulttool export attachments` and parse the resulting manifest by hand — `peekie attachments` already runs that and adds `contentType` and `qualifiedName`.

## See also

- `peekie-tests` — test results, including the `qualifiedName` values you'd pass to `--test-id`. Also supports `--attachments export --attachments-to <dir>` to inline attachments inside the test JSON.
- `peekie` (umbrella) — cross-subcommand recipe for saving failure attachments as CI artifacts.
