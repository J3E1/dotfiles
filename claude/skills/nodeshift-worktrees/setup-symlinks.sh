#!/usr/bin/env bash
# NOTE: Run from the ROOT of a freshly created nodeshift worktree.
# Symlinks node_modules + .env files from the main checkout (Conductor-style).
set -euo pipefail

MAIN_REPO="$(git worktree list | head -1 | awk '{print $1}')"
CURRENT_ROOT="$(git rev-parse --show-toplevel)"

# NOTE: Safety guard — running this in the main checkout would rm -rf the real
# node_modules and symlink them to themselves. Abort hard.
if [ "$CURRENT_ROOT" = "$MAIN_REPO" ]; then
  echo "ERROR: current directory is the MAIN checkout ($MAIN_REPO), not a worktree. Aborting." >&2
  exit 1
fi
cd "$CURRENT_ROOT"

link_dir() {
  rm -rf "$2"
  ln -s "$1" "$2"
}

link_file_if_exists() {
  rm -f "$2"
  if [ -e "$1" ]; then
    ln -s "$1" "$2"
  fi
}

# Symlink all node_modules
link_dir "$MAIN_REPO/apps/nsai/node_modules"                 ./apps/nsai/node_modules
link_dir "$MAIN_REPO/apps/nsai/web/node_modules"             ./apps/nsai/web/node_modules
link_dir "$MAIN_REPO/apps/nsai/frontend-shared/node_modules" ./apps/nsai/frontend-shared/node_modules
link_dir "$MAIN_REPO/apps/nsai/server/node_modules"          ./apps/nsai/server/node_modules
link_dir "$MAIN_REPO/apps/nsai/migrations/node_modules"      ./apps/nsai/migrations/node_modules
link_dir "$MAIN_REPO/apps/nsai/mobile/node_modules"          ./apps/nsai/mobile/node_modules
link_dir "$MAIN_REPO/apps/nsai/landing/node_modules"         ./apps/nsai/landing/node_modules

# Symlink all env files
link_file_if_exists "$MAIN_REPO/apps/nsai/web/.env"         ./apps/nsai/web/.env
link_file_if_exists "$MAIN_REPO/apps/nsai/server/.env"      ./apps/nsai/server/.env
link_file_if_exists "$MAIN_REPO/apps/nsai/migrations/.env"  ./apps/nsai/migrations/.env
link_file_if_exists "$MAIN_REPO/apps/nsai/mobile/.env"      ./apps/nsai/mobile/.env
link_file_if_exists "$MAIN_REPO/apps/nsai/landing/.env"     ./apps/nsai/landing/.env
link_file_if_exists "$MAIN_REPO/apps/nsai/pii-gateway/.env" ./apps/nsai/pii-gateway/.env

echo "Symlinks created in $CURRENT_ROOT (main repo: $MAIN_REPO)"
