#!/usr/bin/env bash
# Run both linters in lint-only mode (no file mutations).
# CI runs the same script; locally we use it as a pre-commit gate.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! command -v mise >/dev/null 2>&1; then
  echo "error: mise is not installed. https://mise.jdx.dev/" >&2
  exit 1
fi

eval "$(mise activate bash)"

echo "→ swiftformat --lint"
swiftformat --lint .

echo "→ swiftlint --strict"
swiftlint --strict --quiet
