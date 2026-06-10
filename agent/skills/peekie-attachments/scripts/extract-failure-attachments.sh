#!/usr/bin/env bash
# Extract attachments from failing tests only into per-test subdirectories.
#
# Usage:
#   extract-failure-attachments.sh <xcresult-path> <output-dir>
#
# Why this exists: `peekie attachments --include failure` only filters the
# printed manifest; it still writes every attachment to disk. The clean
# per-failure layout requires iterating failing test IDs and scoping each
# extraction with --test-id.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <xcresult-path> <output-dir>" >&2
  exit 64
fi

XCRESULT=$1
OUT=$2
mkdir -p "$OUT"

# Pick up `peekie` from PATH; override with PEEKIE env var if needed.
PEEKIE=${PEEKIE:-peekie}

# `qualifiedName` is `Module / Suite / .../ test()`; xcresulttool --test-id
# wants the bare suite-path (no module prefix), so drop the first segment.
#
# Each test gets its own subdirectory under $OUT — `peekie attachments` writes
# `manifest.json` directly into --output-dir, so a shared $OUT collides on the
# second invocation ("Failed to generate manifest.json: file already exists").
"$PEEKIE" tests "$XCRESULT" --format json --include failure \
  | jq -r '.modules[].tests[].qualifiedName | split(" / ") | .[1:] | join("/")' \
  | while read -r id; do
      # Sanitize id into a safe dirname (replace / and parens with _).
      slug=$(printf '%s' "$id" | tr '/()' '___' | tr -s '_')
      sub="$OUT/$slug"
      mkdir -p "$sub"
      "$PEEKIE" attachments "$XCRESULT" --output-dir "$sub" --test-id "$id" --format json >/dev/null
    done
