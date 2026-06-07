#!/usr/bin/env bash
# Apply formatter fixes in place. Run before `git commit`.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! command -v mise >/dev/null 2>&1; then
  echo "error: mise is not installed. https://mise.jdx.dev/" >&2
  exit 1
fi

eval "$(mise activate bash)"

swiftformat .
