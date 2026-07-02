#!/usr/bin/env bash
# NOTE: Run from the ROOT of a nodeshift worktree BEFORE `git worktree remove`.
# Removes the Conductor-style symlinks so removal doesn't trip on untracked files.
set -euo pipefail

MAIN_REPO="$(git worktree list | head -1 | awk '{print $1}')"
CURRENT_ROOT="$(git rev-parse --show-toplevel)"

# NOTE: Safety guard — never run cleanup in the main checkout; the rm targets
# there are the REAL node_modules and .env files.
if [ "$CURRENT_ROOT" = "$MAIN_REPO" ]; then
  echo "ERROR: current directory is the MAIN checkout ($MAIN_REPO), not a worktree. Aborting." >&2
  exit 1
fi
cd "$CURRENT_ROOT"

# NOTE: All of these are symlinks in a worktree; rm -rf on a symlink removes
# the link itself, never the target. No trailing slashes (a trailing slash
# would make rm follow the link into the main repo).
rm -rf  apps/nsai/node_modules \
        apps/nsai/web/node_modules \
        apps/nsai/frontend-shared/node_modules \
        apps/nsai/server/node_modules \
        apps/nsai/migrations/node_modules \
        apps/nsai/mobile/node_modules \
        apps/nsai/landing/node_modules

rm -f   apps/nsai/web/.env \
        apps/nsai/server/.env \
        apps/nsai/migrations/.env \
        apps/nsai/mobile/.env \
        apps/nsai/landing/.env \
        apps/nsai/pii-gateway/.env

echo "Symlinks removed from $CURRENT_ROOT — safe to 'git worktree remove' now"
