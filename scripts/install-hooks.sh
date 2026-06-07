#!/usr/bin/env bash
# Install a pre-commit hook that runs scripts/lint.sh.
# Idempotent — re-running rewrites the hook file.

set -euo pipefail

GIT_DIR="$(git rev-parse --git-common-dir)"
HOOK="$GIT_DIR/hooks/pre-commit"
mkdir -p "$(dirname "$HOOK")"

cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/scripts/lint.sh"
EOF

chmod +x "$HOOK"

echo "Installed $HOOK → runs scripts/lint.sh"
